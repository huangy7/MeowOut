import Foundation
import MemosKit

struct QuickMemoStatusPresentation: Equatable {
    let message: String
    let actionTitle: String?
    let opensMemosSettings: Bool
    let isError: Bool

    static func info(_ message: String) -> QuickMemoStatusPresentation {
        QuickMemoStatusPresentation(
            message: message,
            actionTitle: nil,
            opensMemosSettings: false,
            isError: false
        )
    }
}

enum QuickMemoSaveFailurePresenter {
    static func presentation(for error: Error) -> QuickMemoStatusPresentation {
        guard let memosError = error as? MemosError else {
            return QuickMemoStatusPresentation(
                message: I18n.localized("memos_error_generic"),
                actionTitle: nil,
                opensMemosSettings: false,
                isError: true
            )
        }

        switch memosError {
        case .notConfigured:
            return settingsPresentation(message: I18n.localized("memos_error_not_configured"))
        case .unauthorized:
            return settingsPresentation(message: I18n.localized("memos_error_unauthorized"))
        case .decodingError:
            return errorPresentation(message: I18n.localized("memos_error_parse"))
        case .serverError(let statusCode, _):
            if (400..<500).contains(statusCode) {
                return errorPresentation(message: I18n.localized("memos_error_content_permission"))
            }
            return errorPresentation(message: I18n.localized("memos_error_generic"))
        case .networkError:
            return errorPresentation(message: I18n.localized("memos_error_network"))
        }
    }

    private static func settingsPresentation(message: String) -> QuickMemoStatusPresentation {
        QuickMemoStatusPresentation(
            message: message,
            actionTitle: I18n.localized("memos_action_go_to_settings"),
            opensMemosSettings: true,
            isError: true
        )
    }

    private static func errorPresentation(message: String) -> QuickMemoStatusPresentation {
        QuickMemoStatusPresentation(
            message: message,
            actionTitle: nil,
            opensMemosSettings: false,
            isError: true
        )
    }
}
