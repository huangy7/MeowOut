import Cocoa
import ApplicationServices
import Carbon

public class TextInjector {
    public static let shared = TextInjector()
    private let injectionQueue = DispatchQueue(label: "com.meowout.TextInjectorQueue")
    private var isInjecting = false
    
    private init() {}
    
    public func inject(text: String, title: String) {
        injectionQueue.async {
            guard !self.isInjecting else { return }
            self.isInjecting = true
            self.performInjection(text: text, title: title)
        }
    }
    
    private func performInjection(text: String, title: String) {
        guard AXIsProcessTrusted() else {
            self.isInjecting = false
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .keyDropRequireAccessibility, object: nil)
            }
            return
        }
        
        if IsSecureEventInputEnabled() {
            // Secure input is enabled (e.g. password field)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .keyDropDidInject,
                    object: nil,
                    userInfo: ["status": "secureInputError", "title": title]
                )
            }
            self.isInjecting = false
            return
        }
        
        let pasteboard = NSPasteboard.general
        let backupItems = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let expectedChangeCount = pasteboard.changeCount
        
        self.simulateCmdV()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
            self.injectionQueue.async {
                defer { 
                    self.isInjecting = false 
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: .keyDropDidInject,
                            object: nil,
                            userInfo: ["status": "success", "title": title]
                        )
                    }
                }
                if pasteboard.changeCount == expectedChangeCount {
                    pasteboard.clearContents()
                    if let backupItems = backupItems, !backupItems.isEmpty {
                        pasteboard.writeObjects(backupItems)
                    }
                }
            }
        }
    }
    
    private func simulateCmdV() {
        let vKeyCode: CGKeyCode = 9
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else { return }
        
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
