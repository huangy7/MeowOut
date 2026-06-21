import Foundation
import CryptoKit

public enum ClipboardAssetStoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidFileName(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidFileName(fileName):
            return "Invalid clipboard asset file name: \(fileName)"
        }
    }
}

public struct ClipboardAssetStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public static var applicationSupportStore: ClipboardAssetStore {
        let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return ClipboardAssetStore(
            rootDirectory: applicationSupportDirectory
                .appendingPathComponent("MeowOut", isDirectory: true)
                .appendingPathComponent("ClipboardHistory", isDirectory: true)
                .appendingPathComponent("Assets", isDirectory: true)
        )
    }

    public func write(_ data: Data, preferredExtension: String) throws -> String {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )

        let sanitizedExtension = sanitizeExtension(preferredExtension)
        let fileName = "\(stableIdentifier(for: data)).\(sanitizedExtension)"
        try data.write(to: assetURL(for: fileName), options: .atomic)

        return fileName
    }

    public func read(fileName: String) throws -> Data {
        try Data(contentsOf: assetURL(for: fileName))
    }

    public func delete(fileName: String) throws {
        let fileURL = try assetURL(for: fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: fileURL)
    }

    private func assetURL(for fileName: String) throws -> URL {
        guard isValidFileName(fileName) else {
            throw ClipboardAssetStoreError.invalidFileName(fileName)
        }

        let standardizedRoot = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let fileURL = standardizedRoot
            .appendingPathComponent(fileName, isDirectory: false)
            .standardizedFileURL
            .resolvingSymlinksInPath()

        guard isURL(fileURL, containedIn: standardizedRoot) else {
            throw ClipboardAssetStoreError.invalidFileName(fileName)
        }

        return fileURL
    }

    private func isValidFileName(_ fileName: String) -> Bool {
        guard !fileName.isEmpty,
              fileName != ".",
              !fileName.hasPrefix("/"),
              !fileName.contains("/"),
              !fileName.contains("\\"),
              !fileName.contains("..")
        else {
            return false
        }

        return (fileName as NSString).lastPathComponent == fileName
    }

    private func isURL(_ url: URL, containedIn rootURL: URL) -> Bool {
        let rootPath = rootURL.path
        let filePath = url.path

        return filePath.hasPrefix(rootPath + "/")
    }

    private func sanitizeExtension(_ preferredExtension: String) -> String {
        let trimmedExtension = preferredExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix { $0 == "." }

        guard !trimmedExtension.isEmpty,
              trimmedExtension.unicodeScalars.allSatisfy(isSafeExtensionCharacter)
        else {
            return "bin"
        }

        return String(trimmedExtension)
    }

    private func stableIdentifier(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func isSafeExtensionCharacter(_ scalar: UnicodeScalar) -> Bool {
        let value = scalar.value

        return (65...90).contains(value)
            || (97...122).contains(value)
            || (48...57).contains(value)
            || scalar == "_"
            || scalar == "-"
    }
}
