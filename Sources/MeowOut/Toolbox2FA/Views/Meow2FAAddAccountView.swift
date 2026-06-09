import SwiftUI

public struct Meow2FAAddAccountView: View {
    @Environment(AppState.self) var appState
    @Binding var path: NavigationPath
    @ObservedObject var generator = TOTPGenerator.shared
    
    var editingAccountId: String?
    
    @State private var name: String = ""
    @State private var issuer: String = ""
    @State private var group: String = ""
    @State private var secret: String = ""
    @State private var algorithm: TOTPAlgorithm = .SHA1
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert = false
    
    public init(path: Binding<NavigationPath>, editingAccountId: String? = nil) {
        self._path = path
        self.editingAccountId = editingAccountId
    }
    
    public var body: some View {
        ZStack {
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
                    
                    Text(editingAccountId != nil ? I18n.localized("meow2fa_edit_account", language: appState.language) : I18n.localized("meow2fa_add_account", language: appState.language))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    
                    Spacer()
                    
                    // Placeholder to balance the chevron.left
                    Image(systemName: "chevron.left")
                        .opacity(0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Avatar Placeholder
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: "key.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                        
                        // Form Fields
                        VStack(spacing: 12) {
                            Meow2FATextField(placeholder: I18n.localized("meow2fa_add_account_name", language: appState.language), text: $name, icon: "person.fill")
                            Meow2FATextField(placeholder: I18n.localized("meow2fa_add_account_issuer", language: appState.language), text: $issuer, icon: "building.2.fill")
                            Meow2FATextField(placeholder: I18n.localized("meow2fa_add_account_group", language: appState.language), text: $group, icon: "folder.fill")
                            Meow2FASecureField(placeholder: I18n.localized("meow2fa_add_account_secret", language: appState.language), text: $secret, icon: "lock.fill")
                            
                            Meow2FAPickerField(
                                title: I18n.localized("meow2fa_add_account_algorithm", language: appState.language),
                                selection: $algorithm,
                                options: [.SHA1, .SHA256, .SHA512],
                                icon: "cpu"
                            )
                        }
                        .padding(.horizontal, 24)
                        
                        // Action Buttons
                        HStack(spacing: 16) {
                            if editingAccountId != nil {
                                Button(action: deleteAccount) {
                                    HStack {
                                        Image(systemName: "trash.fill")
                                        Text(I18n.localized("meow2fa_delete_account", language: appState.language))
                                            .font(.system(size: 16, weight: .bold, design: .rounded))
                                    }
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(16)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Button(action: saveAccount) {
                                Text(I18n.localized("meow2fa_add_account_save", language: appState.language))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(isFormValid ? Color.blue : Color.gray.opacity(0.3))
                                    .cornerRadius(16)
                                    .shadow(color: isFormValid ? .blue.opacity(0.3) : .clear, radius: 8, y: 4)
                                    .animation(.spring(), value: isFormValid)
                            }
                            .buttonStyle(.plain)
                            .disabled(!isFormValid)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                    }
                    .padding(.bottom, 40)
                }
            }
            
            if showDeleteConfirmation {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.none) {
                            showDeleteConfirmation = false
                        }
                    }
                
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.1))
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: "trash.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.red)
                        }
                        
                        Text(I18n.localized("meow2fa_delete_confirm_title", language: appState.language))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text(I18n.localized("meow2fa_delete_confirm_desc", language: appState.language))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    }
                    .padding(.top, 8)
                    
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.none) {
                                showDeleteConfirmation = false
                            }
                        } label: {
                            Text(I18n.localized("meow2fa_cancel", language: appState.language))
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.secondary.opacity(0.15))
                                .foregroundColor(.primary)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            confirmDelete()
                            withAnimation(.none) {
                                showDeleteConfirmation = false
                            }
                        } label: {
                            Text(I18n.localized("meow2fa_delete_account", language: appState.language))
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(color: Color.red.opacity(0.3), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
                .background(AnyShapeStyle(.regularMaterial))
                .cornerRadius(24)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 30, y: 15)
                .padding(.horizontal, 40)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text(I18n.localized("error", language: appState.language)),
                message: Text(errorMessage ?? "Unknown error"),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            if let id = editingAccountId {
                if let acc = generator.accounts.first(where: { $0.uuid == id }) {
                    self.name = acc.name
                    self.issuer = acc.issuer
                    self.group = acc.group
                    self.secret = acc.secret
                    self.algorithm = acc.algorithm ?? .SHA1
                } else {
                    path.removeLast()
                }
            }
        }
    }
    
    private var isFormValid: Bool {
        !name.isEmpty && !secret.isEmpty && isValidBase32(secret)
    }
    
    private func isValidBase32(_ str: String) -> Bool {
        let cleaned = str.uppercased().filter { !$0.isWhitespace }
        guard !cleaned.isEmpty else { return false }
        let validChars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567=")
        return cleaned.unicodeScalars.allSatisfy { validChars.contains($0) }
    }
    
    private func saveAccount() {
        if let id = editingAccountId {
            if var account = generator.accounts.first(where: { $0.uuid == id }) {
                account.name = name
                account.issuer = issuer
                account.group = group
                account.secret = secret
                account.algorithm = algorithm
                Task {
                    do {
                        try await generator.updateAccount(account)
                        path.removeLast()
                    } catch {
                        errorMessage = error.localizedDescription
                        showErrorAlert = true
                    }
                }
            }
        } else {
            let account = TOTPAccount(name: name, issuer: issuer, group: group, secret: secret, algorithm: algorithm)
            Task {
                do {
                    try await generator.addAccount(account)
                    path.removeLast()
                } catch {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
    
    private func deleteAccount() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            showDeleteConfirmation = true
        }
    }
    
    private func confirmDelete() {
        if let id = editingAccountId {
            Task {
                do {
                    try await generator.deleteAccount(withId: id)
                    path.removeLast()
                } catch {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
}

struct Meow2FAPickerField<T: Hashable & RawRepresentable>: View where T.RawValue == String {
    let title: String
    @Binding var selection: T
    let options: [T]
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 20)
            
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 100)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AnyShapeStyle(.regularMaterial))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

struct Meow2FATextField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(isFocused ? .blue : .secondary.opacity(0.6))
                .frame(width: 20)
                .scaleEffect(isFocused ? 1.1 : 1.0)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isFocused ? AnyShapeStyle(.background) : AnyShapeStyle(.regularMaterial))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? Color.blue : Color.primary.opacity(0.05), lineWidth: isFocused ? 2 : 1)
        )
        .shadow(color: isFocused ? Color.blue.opacity(0.15) : .clear, radius: 8, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
    }
}

struct Meow2FASecureField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    
    @FocusState private var isFocused: Bool
    @State private var isVisible: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(isFocused ? .blue : .secondary.opacity(0.6))
                .frame(width: 20)
                .scaleEffect(isFocused ? 1.1 : 1.0)
            
            Group {
                if isVisible {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($isFocused)
                } else {
                    SecureField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($isFocused)
                }
            }
            
            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isFocused ? AnyShapeStyle(.background) : AnyShapeStyle(.regularMaterial))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? Color.blue : Color.primary.opacity(0.05), lineWidth: isFocused ? 2 : 1)
        )
        .shadow(color: isFocused ? Color.blue.opacity(0.15) : .clear, radius: 8, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
    }
}
