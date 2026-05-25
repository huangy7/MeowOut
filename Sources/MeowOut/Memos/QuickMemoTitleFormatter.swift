import Foundation

enum QuickMemoTitleFormatter {
    static func title(for content: String, fallback: String = I18n.localized("memos_quick_title_default"), maxLength: Int = 80) -> String {
        let firstLine = content
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !firstLine.isEmpty else {
            return fallback
        }

        guard firstLine.count > maxLength else {
            return firstLine
        }

        return "\(firstLine.prefix(maxLength))..."
    }
}
