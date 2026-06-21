import Foundation

public enum ClipboardPanelSelectionCoordinator {
    public static func chooseAfterDismiss(
        dismiss: @escaping () -> Void,
        choose: @escaping () -> Void
    ) {
        dismiss()
        DispatchQueue.main.async(execute: choose)
    }
}
