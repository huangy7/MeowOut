import Foundation
import OSLog

public enum JSONStorage {
    private static let logger = Logger(subsystem: "com.meowout", category: "JSONStorage")

    /// Asynchronously encodes and writes the object to the specified URL.
    /// This method offloads the disk I/O and JSON encoding to a background detached task,
    /// preventing main-thread stalls.
    /// - Note: Ensure `object` is a value type (struct/array) or thread-safe, 
    /// and capture a snapshot under a lock before passing it here if needed.
    public static func save<T: Encodable & Sendable>(_ object: T, to url: URL, encoderFactory: @Sendable @escaping () -> JSONEncoder = { JSONEncoder() }) {
        Task.detached(priority: .background) {
            do {
                let encoder = encoderFactory()
                let data = try encoder.encode(object)
                try data.write(to: url, options: .atomic)
            } catch {
                logger.error("Failed to save JSON to \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
