import SwiftUI
import AppKit

public struct Meow2FASettingsView: View {
    @Environment(AppState.self) var appState
    @Binding var path: NavigationPath
    @ObservedObject var generator = TOTPGenerator.shared
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    
    public init(path: Binding<NavigationPath>) {
        self._path = path
    }
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        path.removeLast()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Text(I18n.localized("meow2fa_settings", language: appState.language))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    
                    Spacer()
                    
                    Image(systemName: "chevron.left")
                        .opacity(0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
                
                // List
                ScrollView {
                    VStack(spacing: 12) {
                        Meow2FASettingCard(
                            icon: "square.and.arrow.down.fill",
                            title: I18n.localized("meow2fa_import", language: appState.language),
                            desc: I18n.localized("meow2fa_import_desc", language: appState.language),
                            action: importJSON
                        )
                        
                        Meow2FASettingCard(
                            icon: "square.and.arrow.up.fill",
                            title: I18n.localized("meow2fa_export", language: appState.language),
                            desc: I18n.localized("meow2fa_export_desc", language: appState.language),
                            action: exportJSON
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
            }
            
            if let msg = toastMessage {
                Text(msg)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.8))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: toastMessage)
    }
    
    private func showToast(message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled && toastMessage == message {
                toastMessage = nil
            }
        }
    }
    
    private func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            Task.detached {
                do {
                    let data = try Data(contentsOf: url)
                    let imported = try JSONDecoder().decode([TOTPAccount].self, from: data)
                    
                    let currentAccounts = await generator.accounts
                    var newAccounts: [TOTPAccount] = []
                    for account in imported {
                        if !currentAccounts.contains(where: { $0.uuid == account.uuid }) {
                            newAccounts.append(account)
                        }
                    }
                    
                    if !newAccounts.isEmpty {
                        try await generator.addAccounts(newAccounts)
                    }
                    
                    let importedCount = newAccounts.count
                    await MainActor.run {
                        if importedCount > 0 {
                            showToast(message: String(format: I18n.localized("meow2fa_import_success", language: appState.language), importedCount))
                        } else {
                            showToast(message: I18n.localized("meow2fa_import_no_new", language: appState.language))
                        }
                    }
                } catch {
                    await MainActor.run {
                        showToast(message: I18n.localized("meow2fa_import_failed", language: appState.language))
                        print("Import error: \(error)")
                    }
                }
            }
        }
    }
    
    private func exportJSON() {
        let alert = NSAlert()
        alert.messageText = I18n.localized("meow2fa_export_warning_title", language: appState.language)
        alert.informativeText = I18n.localized("meow2fa_export_warning_desc", language: appState.language)
        alert.alertStyle = .warning
        alert.addButton(withTitle: I18n.localized("continue", language: appState.language))
        alert.addButton(withTitle: I18n.localized("cancel", language: appState.language))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Meow2FA_Export.json"
        
        if panel.runModal() == .OK, let url = panel.url {
            let accountsToExport = generator.accounts
            Task.detached {
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let data = try encoder.encode(accountsToExport)
                    try data.write(to: url, options: .completeFileProtection)
                    await MainActor.run {
                        showToast(message: I18n.localized("meow2fa_export_success", language: appState.language))
                    }
                } catch {
                    await MainActor.run {
                        showToast(message: I18n.localized("meow2fa_export_failed", language: appState.language))
                        print("Export error: \(error)")
                    }
                }
            }
        }
    }
}

struct Meow2FASettingCard: View {
    let icon: String
    let title: String
    let desc: String
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .foregroundColor(.blue)
                        .font(.system(size: 18))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(desc)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(.regularMaterial)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(isHovered ? 0.05 : 0), radius: 8, y: 4)
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
