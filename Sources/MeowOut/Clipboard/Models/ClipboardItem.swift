import Foundation

public struct ClipboardItem: Codable, Identifiable, Hashable, Sendable {
    public enum PrimaryKind: String, Codable, Sendable {
        case text
        case richText
        case image
        case file
        case mixed
        case unknown
    }

    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var lastCopiedAt: Date
    public var copyCount: Int
    public var sourceBundleIdentifier: String?
    public var sourceApplicationName: String?
    public var sourceApplicationIconFileName: String?
    public var isPinned: Bool
    public var contents: [ClipboardContent]

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        lastCopiedAt: Date = Date(),
        copyCount: Int = 1,
        contents: [ClipboardContent],
        sourceBundleIdentifier: String?,
        sourceApplicationName: String? = nil,
        sourceApplicationIconFileName: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.lastCopiedAt = lastCopiedAt
        self.copyCount = copyCount
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceApplicationName = sourceApplicationName
        self.sourceApplicationIconFileName = sourceApplicationIconFileName
        self.isPinned = isPinned
        self.contents = contents
    }

    public var primaryKind: PrimaryKind {
        let kinds = contents
            .filter { $0.type != ClipboardContent.internalMarkerType }
            .map(\.kind)

        if kinds.contains(.image) {
            return .image
        }

        if kinds.contains(.file) {
            return .file
        }

        if kinds.contains(.richText) {
            return .richText
        }

        if kinds.contains(.text) {
            return .text
        }

        return .unknown
    }

    public var primaryPreview: String {
        if let previewText = contents
            .lazy
            .compactMap(\.previewText)
            .first(where: { !$0.isEmpty }) {
            return previewText
        }

        if let fileName = contents
            .lazy
            .flatMap(\.fileNames)
            .first(where: { !$0.isEmpty }) {
            return fileName
        }

        return title
    }

    public func hasSameEffectiveContents(as other: ClipboardItem) -> Bool {
        supersedes(other) && other.supersedes(self)
    }

    public func supersedes(_ other: ClipboardItem) -> Bool {
        let current = effectiveContentSet
        let other = other.effectiveContentSet
        guard !current.isEmpty, !other.isEmpty else {
            return false
        }

        return other.allSatisfy { current.contains($0) }
    }

    private var effectiveContentSet: Set<EffectiveContent> {
        Set(
            contents
                .filter { !$0.isTransientForHistoryComparison }
                .map {
                    EffectiveContent(
                        type: $0.effectiveComparisonType,
                        data: $0.effectiveComparisonData
                    )
                }
        )
    }
}

private struct EffectiveContent: Hashable {
    let type: String
    let data: Data
}
