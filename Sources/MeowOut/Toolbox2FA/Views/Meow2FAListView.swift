import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AccountDropDelegate: DropDelegate {
    let item: TOTPAccount
    @Binding var draggedItem: TOTPAccount?
    
    func dropEntered(info: DropInfo) {
        guard let draggedItem = self.draggedItem else { return }
        guard draggedItem.uuid != item.uuid else { return }
        
        let generator = TOTPGenerator.shared
        guard let fromIndex = generator.accounts.firstIndex(where: { $0.uuid == draggedItem.uuid }),
              let toIndex = generator.accounts.firstIndex(where: { $0.uuid == item.uuid }) else { return }
        
        if fromIndex != toIndex {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                generator.accounts.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        self.draggedItem = nil
        Task {
            try? await TOTPGenerator.shared.saveAccounts()
        }
        return true
    }
}

public struct Meow2FAListView: View {
    @Environment(AppState.self) var appState
    @Binding var path: NavigationPath
    @ObservedObject private var generator = TOTPGenerator.shared
    @State private var searchText = ""
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var draggedItem: TOTPAccount?
    
    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Meow2FA")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    HStack(spacing: 16) {
                        Button(action: { path.append(Meow2FARoute.addAccount) }) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                                .frame(width: 36, height: 36)
                                .background(.regularMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { path.append(Meow2FARoute.settings) }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                                .frame(width: 36, height: 36)
                                .background(.regularMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
                
                // Search
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField(I18n.localized("meow2fa_search", language: appState.language), text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(12)
                .background(.regularMaterial)
                .cornerRadius(12)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                
                // Scrollable List
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredAccounts) { account in
                            let codeInfo = generator.currentCodes[account.uuid]
                            
                            Group {
                                if searchText.isEmpty {
                                    Meow2FAItemCard(
                                        account: account,
                                        info: codeInfo,
                                        progress: codeInfo?.progress ?? 0.0,
                                        timeRemaining: Int(TimeInterval(account.period ?? 30) * (1.0 - (codeInfo?.progress ?? 0.0))),
                                        onCopy: { handleCopy(account: account) },
                                        onEdit: { path.append(Meow2FARoute.editAccount(account.uuid)) },
                                        language: appState.language
                                    )
                                    .onDrag {
                                        self.draggedItem = account
                                        return NSItemProvider(object: account.uuid as NSString)
                                    }
                                    .onDrop(of: [.text], delegate: AccountDropDelegate(item: account, draggedItem: $draggedItem))
                                } else {
                                    Meow2FAItemCard(
                                        account: account,
                                        info: codeInfo,
                                        progress: codeInfo?.progress ?? 0.0,
                                        timeRemaining: Int(TimeInterval(account.period ?? 30) * (1.0 - (codeInfo?.progress ?? 0.0))),
                                        onCopy: { handleCopy(account: account) },
                                        onEdit: { path.append(Meow2FARoute.editAccount(account.uuid)) },
                                        language: appState.language
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            
            // Toast
            if let msg = toastMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.system(size: 14))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial)
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                        .padding(.bottom, 40)
                }
            }
        }
    }
    
    private var filteredAccounts: [TOTPAccount] {
        if searchText.isEmpty { return generator.accounts }
        return generator.accounts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.issuer.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private func handleCopy(account: TOTPAccount) {
        if let code = generator.currentCodes[account.uuid]?.code.replacingOccurrences(of: " ", with: ""), code != "------" {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(code, forType: .string)
            toastTask?.cancel()
            let msg = I18n.localized("meow2fa_copy_success", language: appState.language)
            toastMessage = msg
            toastTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if !Task.isCancelled && toastMessage == msg { toastMessage = nil }
            }
        }
    }
}

struct Meow2FAItemCard: View {
    let account: TOTPAccount
    let info: TOTPCodeInfo?
    let progress: Double
    let timeRemaining: Int
    let onCopy: () -> Void
    let onEdit: (() -> Void)?
    let language: AppState.AppLanguage
    
    @State private var isHovered = false
    
    var avatarLetter: String {
        if !account.issuer.isEmpty, let first = account.issuer.first {
            return String(first).uppercased()
        }
        if !account.name.isEmpty, let first = account.name.first {
            return String(first).uppercased()
        }
        return "?"
    }
    
    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: 16) {
                // Avatar
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(avatarLetter)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.blue)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    let topText = account.issuer.isEmpty ? account.name : "\(account.issuer) (\(account.name))"
                    Text(topText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    let code = info?.code ?? "------"
                    Text(code)
                        .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                if isHovered {
                    HStack(spacing: 12) {
                        if let onEdit = onEdit {
                            Button(action: onEdit) {
                                Image(systemName: "pencil")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    ProgressRingView(progress: progress, timeRemaining: timeRemaining)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(.regularMaterial)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(isHovered ? 0.08 : 0.03), radius: isHovered ? 12 : 6, y: isHovered ? 6 : 3)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
