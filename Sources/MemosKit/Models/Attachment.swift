import Foundation

public struct Attachment: Codable, Equatable, Sendable {
    public let name: String
    public let filename: String
    public let type: String
    public let size: Int64
    public let createTime: Date?

    enum CodingKeys: String, CodingKey {
        case name
        case filename
        case type
        case size
        case createTime = "createTime"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.filename = try container.decode(String.self, forKey: .filename)
        self.type = try container.decode(String.self, forKey: .type)
        self.createTime = try container.decodeIfPresent(Date.self, forKey: .createTime)

        // Memos server serializes int64 (size) as string in JSON (e.g. "size": "84364").
        // We decode from both String or Int64 to ensure maximum compatibility.
        if let sizeInt = try? container.decode(Int64.self, forKey: .size) {
            self.size = sizeInt
        } else if let sizeStr = try? container.decode(String.self, forKey: .size), let sizeInt = Int64(sizeStr) {
            self.size = sizeInt
        } else {
            throw DecodingError.dataCorruptedError(forKey: .size, in: container, debugDescription: "Invalid size format")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(filename, forKey: .filename)
        try container.encode(type, forKey: .type)
        try container.encode(createTime, forKey: .createTime)
        try container.encode(String(size), forKey: .size)
    }
}

extension Attachment {
    public var isImage: Bool {
        if type.hasPrefix("image/") {
            return true
        }
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "heic", "tiff"]
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    public var isVideo: Bool {
        if type.hasPrefix("video/") {
            return true
        }
        let videoExtensions = ["mp4", "mov", "avi", "mkv", "webm"]
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        return videoExtensions.contains(ext)
    }

    public var isAudio: Bool {
        if type.hasPrefix("audio/") {
            return true
        }
        let audioExtensions = ["mp3", "wav", "ogg", "m4a", "flac", "aac", "wma"]
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        return audioExtensions.contains(ext)
    }
}

