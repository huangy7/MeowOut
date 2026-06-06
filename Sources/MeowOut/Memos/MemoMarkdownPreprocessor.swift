enum MemoMarkdownPreprocessor {
    static func renderableMarkdown(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var result = ""
        var isInsideFencedCodeBlock = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            result += line

            if index < lines.count - 1 {
                if !isInsideFencedCodeBlock && !isFenceLine(trimmed) && !trimmed.isEmpty && !line.hasSuffix("  ") {
                    result += "  "
                }
                result += "\n"
            }

            if isFenceLine(trimmed) {
                isInsideFencedCodeBlock.toggle()
            }
        }

        return result
    }

    private static func isFenceLine(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("```")
    }
}
