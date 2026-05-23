import SwiftUI

struct KeyboardCleaningOverlayView: View {
    let language: AppState.AppLanguage
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 52))
                .foregroundStyle(.orange)

            Text(I18n.localized("keyboard_cleaning_title", language: language))
                .font(.title2.bold())

            Text(I18n.localized("keyboard_cleaning_desc", language: language))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)

            Button(I18n.localized("keyboard_cleaning_exit", language: language)) {
                onExit()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(40)
    }
}
