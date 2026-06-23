import Foundation
import MemosKit

struct QuickMemoStatusPresentation: Equatable {
    let message: String
    let rawErrorContent: String?
    let actionTitle: String?
    let opensMemosSettings: Bool
    let isError: Bool

    static func info(_ message: String) -> QuickMemoStatusPresentation {
        QuickMemoStatusPresentation(
            message: message,
            rawErrorContent: nil,
            actionTitle: nil,
            opensMemosSettings: false,
            isError: false
        )
    }

    static func error(_ message: String, rawErrorContent: String? = nil) -> QuickMemoStatusPresentation {
        QuickMemoStatusPresentation(
            message: message,
            rawErrorContent: rawErrorContent,
            actionTitle: nil,
            opensMemosSettings: false,
            isError: true
        )
    }
}

enum QuickMemoSaveFailurePresenter {
    static func presentation(for error: Error) -> QuickMemoStatusPresentation {
        guard let memosError = error as? MemosError else {
            return QuickMemoStatusPresentation(
                message: I18n.localized("memos_error_generic"),
                rawErrorContent: nil,
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
        case .serverError(let statusCode, let message):
            if (400..<500).contains(statusCode) {
                let defaultHttpMsg = HTTPURLResponse.localizedString(forStatusCode: statusCode)
                if !message.isEmpty && message != defaultHttpMsg {
                    if let localizedDetail = localizedServerMessage(for: message) {
                        return errorPresentation(message: "保存失败：\(localizedDetail)", rawErrorContent: message)
                    }
                    return errorPresentation(message: "保存失败：\(message)", rawErrorContent: message)
                }
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
            rawErrorContent: nil,
            actionTitle: I18n.localized("memos_action_go_to_settings"),
            opensMemosSettings: true,
            isError: true
        )
    }

    private static func errorPresentation(message: String, rawErrorContent: String? = nil) -> QuickMemoStatusPresentation {
        QuickMemoStatusPresentation(
            message: message,
            rawErrorContent: rawErrorContent,
            actionTitle: nil,
            opensMemosSettings: false,
            isError: true
        )
    }

    private static func localizedServerMessage(for rawMessage: String) -> String? {
        let lower = rawMessage.lowercased()
        if lower.contains("content too long") {
            return "内容过长，超过了系统字数限制"
        }
        if lower.contains("invalid or expired token") || lower.contains("invalid token") {
            return "认证已过期，请重新配置访问令牌"
        }
        if lower.contains("permission denied") {
            return "没有足够的权限执行此操作"
        }
        if lower.contains("user not authenticated") {
            return "用户未登录或认证失败"
        }
        if lower.contains("memo not found") {
            return "备忘录不存在"
        }
        if lower.contains("too many requests") {
            return "请求过于频繁，请稍后再试"
        }
        return nil
    }
}
