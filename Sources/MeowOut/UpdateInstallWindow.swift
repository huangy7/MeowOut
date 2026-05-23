import SwiftUI
import AppKit

/// A custom floating window for displaying the update installation prompt.
final class UpdateInstallWindow: NSWindow {
    static var shared: UpdateInstallWindow?
    
    init(version: String, language: AppState.AppLanguage, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        // Retrieve appState from AppDelegate
        let appState = (NSApp.delegate as? AppDelegate)?.appState ?? AppState()
        
        let contentView = UpdateInstallView(
            version: version,
            language: language,
            appState: appState,
            onConfirm: {
                onConfirm()
                DispatchQueue.main.async {
                    Self.shared?.close()
                    Self.shared = nil
                }
            },
            onCancel: {
                onCancel()
                DispatchQueue.main.async {
                    Self.shared?.close()
                    Self.shared = nil
                }
            }
        )
        
        let hostingController = NSHostingController(rootView: contentView)
        
        // Standard macOS alert size: 300 x 220
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 220),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.contentViewController = hostingController
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .floating // Keep it on top of main app windows
        self.isReleasedWhenClosed = false
        
        // Center the window on the main screen
        if let mainScreen = NSScreen.main {
            let screenFrame = mainScreen.visibleFrame
            let x = screenFrame.origin.x + (screenFrame.width - 300) / 2
            let y = screenFrame.origin.y + (screenFrame.height - 220) / 2
            self.setFrame(NSRect(x: x, y: y, width: 300, height: 220), display: true)
        } else {
            self.center()
        }
    }
    
    override var canBecomeKey: Bool {
        return true
    }
}

struct UpdateInstallView: View {
    let version: String
    let language: AppState.AppLanguage
    @Bindable var appState: AppState
    
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @State private var isFloating = false
    
    var body: some View {
        ZStack {
            AlertVisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Mascot Header
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 56, height: 56)
                    
                    // Mascot display
                    Group {
                        switch appState.selectedPet {
                        case .clawd: ClawdView(pose: .rest, height: 36)
                        case .robot: TerminalView(pose: .rest, height: 36)
                        case .cloud: CloudView(pose: .rest, height: 36)
                        case .horse: HorseView(pose: .rest, height: 36)
                        case .fomo: FomoView(pose: .rest, height: 36)
                        }
                    }
                    .offset(y: isFloating ? -3 : 3)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: isFloating)
                }
                .padding(.top, 16)
                .onAppear {
                    isFloating = true
                }
                
                // Title
                Text(I18n.localizedFormat("update_alert_title", language: language, version))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                    .multilineTextAlignment(.center)
                
                // Body/Description text
                Text(I18n.localized("update_alert_body", language: language))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .padding(.top, 8)
                    .padding(.horizontal, 20)
                    .multilineTextAlignment(.center)
                
                Spacer(minLength: 12)
                
                // Custom Premium Buttons
                HStack(spacing: 12) {
                    AlertButton(
                        title: I18n.localized("update_alert_cancel", language: language),
                        isPrimary: false,
                        action: onCancel
                    )
                    
                    AlertButton(
                        title: I18n.localized("update_alert_confirm", language: language),
                        isPrimary: true,
                        action: onConfirm
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 300, height: 220)
    }
}

private struct AlertButton: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isPrimary ? .semibold : .regular))
                .foregroundStyle(isPrimary ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isPrimary ?
                              (isHovered ? Color.blue.opacity(0.85) : Color.blue) :
                              (isHovered ? Color.primary.opacity(0.1) : Color.primary.opacity(0.05))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isPrimary ? Color.clear : Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

private struct AlertVisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
