import Cocoa
import SwiftUI

class ClickThroughVisualEffectView: NSVisualEffectView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

@MainActor
public class FloatingPanelController: NSPanel {
    public static let shared = FloatingPanelController()
    
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    
    let viewModel = PanelViewModel()
    
    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = .popUpMenu
        self.isFloatingPanel = true
        self.worksWhenModal = true
        self.hidesOnDeactivate = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        
        let visualEffect = ClickThroughVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        
        let hostingView = NSHostingView(rootView: FloatingPanelView(viewModel: viewModel))
        visualEffect.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor)
        ])
        
        self.contentView = visualEffect
    }
    
    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
    
    public func show() {
        viewModel.isPanelVisible = true
        viewModel.reset()
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        
        var panelRect = self.frame
        panelRect.origin.x = mouseLocation.x - panelRect.width / 2
        panelRect.origin.y = mouseLocation.y - panelRect.height - 20
        
        if let screenFrame = screen?.visibleFrame {
            if panelRect.minX < screenFrame.minX { panelRect.origin.x = screenFrame.minX + 10 }
            if panelRect.maxX > screenFrame.maxX { panelRect.origin.x = screenFrame.maxX - panelRect.width - 10 }
            if panelRect.minY < screenFrame.minY { panelRect.origin.y = screenFrame.minY + 10 }
            if panelRect.maxY > screenFrame.maxY { panelRect.origin.y = screenFrame.maxY - panelRect.height - 10 }
        }
        
        self.setFrame(panelRect, display: true)
        self.makeKeyAndOrderFront(nil)
        
        setupMonitors()
        
        NotificationCenter.default.post(name: .keyDropPanelDidShow, object: nil)
    }
    
    public func hide() {
        viewModel.isPanelVisible = false
        self.orderOut(nil)
        removeMonitors()
    }
    
    private func setupMonitors() {
        removeMonitors()
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.handleKeyDown(event) {
                return nil
            }
            return event
        }
    }
    
    private func removeMonitors() {
        if let global = globalEventMonitor {
            NSEvent.removeMonitor(global)
            globalEventMonitor = nil
        }
        if let local = localEventMonitor {
            NSEvent.removeMonitor(local)
            localEventMonitor = nil
        }
    }
    
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        let isCommand = event.modifierFlags.contains(.command)
        switch keyCode {
        case 53: // ESC
            hide()
            return true
        case 125: // Down Arrow
            viewModel.moveSelection(up: false)
            return true
        case 126: // Up Arrow
            viewModel.moveSelection(up: true)
            return true
        case 36, 76: // Enter
            if let snippet = viewModel.selectedSnippet {
                inject(snippet: snippet)
            }
            return true
        case 51: // Delete
            if !isCommand {
                viewModel.removeLastCharacter()
                return true
            }
            return false
        default:
            if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
                // ⌘+number: inject snippet at that index
                if isCommand, chars.count == 1, let num = Int(chars), num >= 1, num <= 9 {
                    if let snippet = viewModel.snippet(at: num - 1) {
                        inject(snippet: snippet)
                        return true
                    }
                }
                // Regular keys (including numbers): add to search
                if !isCommand, chars.rangeOfCharacter(from: .controlCharacters) == nil {
                    viewModel.appendSearch(chars)
                    return true
                }
            }
        }
        return false
    }
    
    func inject(snippet: Snippet) {
        hide()
        TextInjector.shared.inject(text: snippet.content, title: snippet.title)
    }
    
    public override var canBecomeKey: Bool {
        return true
    }
}
