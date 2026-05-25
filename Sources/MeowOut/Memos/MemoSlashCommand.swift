import Foundation

public enum MemoSlashCommand: String, CaseIterable, Equatable, Sendable {
    case todo
    case code
    case link
    case table

    public var template: String {
        switch self {
        case .todo:
            "- [ ] "
        case .code:
            "```\n\n```"
        case .link:
            "[text](url)"
        case .table:
            "| Header | Header |\n| ------ | ------ |\n| Cell   | Cell |"
        }
    }

    public var displayText: String {
        "/\(rawValue)"
    }

    public var cursorOffsetInTemplate: Int {
        switch self {
        case .todo:
            template.count
        case .code:
            4
        case .link, .table:
            1
        }
    }

    public static func matching(query: String) -> [MemoSlashCommand] {
        let normalizedQuery = query.lowercased()
        guard !normalizedQuery.isEmpty else {
            return allCases
        }

        return allCases.filter { command in
            command.rawValue.hasPrefix(normalizedQuery)
        }
    }

    public func apply(to text: String, triggerRange: Range<Int>) -> (text: String, cursorOffset: Int) {
        let lowerIndex = text.index(text.startIndex, offsetBy: triggerRange.lowerBound)
        let upperIndex = text.index(text.startIndex, offsetBy: triggerRange.upperBound)
        let replacementRange = lowerIndex..<upperIndex
        let updatedText = text.replacingCharacters(in: replacementRange, with: template)

        return (
            text: updatedText,
            cursorOffset: triggerRange.lowerBound + cursorOffsetInTemplate
        )
    }
}

public struct MemoSlashCommandTrigger: Equatable, Sendable {
    public let query: String
    public let range: Range<Int>

    public init(query: String, range: Range<Int>) {
        self.query = query
        self.range = range
    }

    public static func detect(in text: String, cursorOffset: Int) -> MemoSlashCommandTrigger? {
        let characters = Array(text)
        guard (0...characters.count).contains(cursorOffset), cursorOffset > 0 else {
            return nil
        }

        let slashIndex: Int
        let characterBeforeCursor = characters[cursorOffset - 1]
        if characterBeforeCursor == "/" {
            slashIndex = cursorOffset - 1
        } else if characterBeforeCursor.isMemoSlashCommandQueryCharacter {
            var index = cursorOffset - 1
            while index >= 0, characters[index].isMemoSlashCommandQueryCharacter {
                index -= 1
            }

            guard index >= 0, characters[index] == "/" else {
                return nil
            }
            slashIndex = index
        } else {
            return nil
        }

        if slashIndex > 0 {
            guard characters[slashIndex - 1].isWhitespace else {
                return nil
            }
        }

        let queryCharacters = characters[(slashIndex + 1)..<cursorOffset]
        return MemoSlashCommandTrigger(
            query: String(queryCharacters),
            range: slashIndex..<cursorOffset
        )
    }
}

private extension Character {
    var isMemoSlashCommandQueryCharacter: Bool {
        unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }
}
