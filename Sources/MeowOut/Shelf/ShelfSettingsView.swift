import SwiftUI
import KeyboardShortcuts

struct ShelfSettingsView: View {
    @Environment(AppState.self) private var state
    @AppStorage("shelfEnabled") private var shelfEnabled = true
    @AppStorage("shelfShakeToOpen") private var shelfShakeToOpen = true

    var body: some View {
        SettingsGroup {
            SettingsRow(I18n.localized("shelf_settings_enabled", language: state.language),
                        description: I18n.localized("shelf_settings_enabled_desc", language: state.language)) {
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

            Group {
                SettingsRowDivider()
                SettingsRow(I18n.localized("shelf_settings_shortcut", language: state.language)) {
                    KeyboardShortcuts.Recorder(for: .toggleShelf)
                }
                SettingsRowDivider()
                SettingsRow(I18n.localized("shelf_settings_shake", language: state.language)) {
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
            }
            .disabled(!shelfEnabled)
            .opacity(shelfEnabled ? 1.0 : 0.5)
        }
    }
}
