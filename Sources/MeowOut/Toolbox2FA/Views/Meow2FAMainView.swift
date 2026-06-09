import SwiftUI

public enum Meow2FARoute: Hashable {
    case settings
    case addAccount
    case editAccount(String)
}

public struct Meow2FAMainView: View {
    @State private var path = NavigationPath()
    
    public init() {}
    
    public var body: some View {
        Meow2FAGlassBackground {
            NavigationStack(path: $path) {
                Meow2FAListView(path: $path)
                    .navigationDestination(for: Meow2FARoute.self) { route in
                        switch route {
                        case .settings:
                            Meow2FASettingsView(path: $path)
                                .navigationBarBackButtonHidden(true)
                        case .addAccount:
                            Meow2FAAddAccountView(path: $path)
                                .navigationBarBackButtonHidden(true)
                        case .editAccount(let id):
                            Meow2FAAddAccountView(path: $path, editingAccountId: id)
                                .navigationBarBackButtonHidden(true)
                        }
                    }
            }
        }
        .frame(minWidth: 380, minHeight: 500)
    }
}
