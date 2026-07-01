import SwiftUI
import KeyboardShortcuts

struct ShelfSettingsView: View {
    @Environment(AppState.self) private var state
    @AppStorage("shelfEnabled") private var shelfEnabled = true
    @AppStorage("shelfShakeToOpen") private var shelfShakeToOpen = true

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(
                icon: "tray.full.fill",
                iconColor: .blue,
                title: I18n.localized("settings_tab_shelf", language: state.language),
                description: I18n.localized("shelf_settings_enabled_desc", language: state.language)
            ) {
                VStack(spacing: 16) {
                    HStack {
                        Text(I18n.localized("shelf_settings_enabled", language: state.language))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { shelfEnabled },
                            set: { newValue in
                                shelfEnabled = newValue
                                ShelfService.shared.syncWithPreferences()
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    HStack {
                        Text(I18n.localized("shelf_settings_shortcut", language: state.language))
                        Spacer()
                        KeyboardShortcuts.Recorder(for: .toggleShelf)
                    }
                    .disabled(!shelfEnabled)
                    .opacity(shelfEnabled ? 1.0 : 0.5)

                    HStack {
                        Text(I18n.localized("shelf_settings_shake", language: state.language))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { shelfShakeToOpen },
                            set: { newValue in
                                shelfShakeToOpen = newValue
                                ShelfService.shared.syncShakeMonitor()
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .disabled(!shelfEnabled)
                    .opacity(shelfEnabled ? 1.0 : 0.5)
                }
            }
        }
    }
}
