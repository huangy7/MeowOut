import Foundation
import OSLog

public enum JSONStorage {
    private static let logger = Logger(subsystem: "com.meowout", category: "JSONStorage")

    /// Asynchronously encodes and writes the object to the specified URL.
    /// This method offloads the disk I/O and JSON encoding to a background detached task,
    /// preventing main-thread stalls.
    /// - Note: Ensure `object` is a value type (struct/array) or thread-safe,
    /// and capture a snapshot under a lock before passing it here if needed.
    /// - Returns: 写入任务。调用方可忽略它（保持非阻塞语义），也可 await 它以确定性地
    ///   等待落盘完成 —— 后台任务的调度时机取决于机器负载，按固定时长猜测并不可靠。
    @discardableResult
    public static func save<T: Encodable & Sendable>(_ object: T, to url: URL, encoderFactory: @Sendable @escaping () -> JSONEncoder = { JSONEncoder() }) -> Task<Void, Never> {
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
