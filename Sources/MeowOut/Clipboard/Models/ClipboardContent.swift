import Foundation

public struct ClipboardContent: Codable, Hashable, Sendable {
    public static let internalMarkerType = "org.meowout.clipboardHistory"
    public static let transientComparisonTypes: Set<String> = [
        internalMarkerType,
        "x.nspasteboard.ModifiedType",
        "org.p0deje.Maccy",
        "com.apple.flat-rtfd",
        "com.apple.finder.node",
        "com.apple.linkpresentation.metadata",
        "com.apple.notes.richtext",
        "com.apple.WebKit.custom-pasteboard-data",
        "org.chromium.source-url",
        "org.chromium.source-token",
        "org.chromium.web-custom-data",
    ]

    public enum Storage: Codable, Hashable, Sendable {
        case inlineText(String)
        case inlineData(Data)
        case asset(fileName: String)
    }

    public enum Kind: String, Codable, Sendable {
        case text
        case richText
        case image
        case file
        case unknown
    }

    public let type: String
    public let storage: Storage
    public let previewText: String?
    public let fileNames: [String]
    public let imageWidth: Double?
    public let imageHeight: Double?

    public init(
        type: String,
        storage: Storage,
        previewText: String? = nil,
        fileNames: [String] = [],
        imageWidth: Double? = nil,
        imageHeight: Double? = nil
    ) {
        self.type = type
        self.storage = storage
        self.previewText = previewText
        self.fileNames = fileNames
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    public var kind: Kind {
        switch type {
        case "public.utf8-plain-text", "NSStringPboardType", "public.text":
            return .text
        case "public.rtf", "public.html":
            return .richText
        case "public.png", "public.tiff", "public.jpeg", "public.heic", "com.compuserve.gif":
            return .image
        case "public.file-url":
            return .file
        default:
            return .unknown
        }
    }

    public var effectiveHashData: Data {
        switch storage {
        case let .inlineText(text):
            return Data(text.utf8)
        case let .inlineData(data):
            return data
        case let .asset(fileName):
            return Data(fileName.utf8)
        }
    }

    public var effectiveComparisonType: String {
        switch kind {
        case .text:
            return "org.meowout.clipboard.normalized-text"
        default:
            return type
        }
    }

    public var effectiveComparisonData: Data {
        guard kind == .text else {
            return effectiveHashData
        }

        if case let .inlineText(text) = storage {
            return Data(text.utf8)
        }

        if case let .inlineData(data) = storage,
           let text = String(data: data, encoding: .utf8) {
            return Data(text.utf8)
        }

        return effectiveHashData
    }

    public var isTransientForHistoryComparison: Bool {
        ClipboardContent.transientComparisonTypes.contains(type)
            || type.hasPrefix("dyn.")
            || type.hasPrefix("com.microsoft.ole.source.")
    }
}
