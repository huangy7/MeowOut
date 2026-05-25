import Foundation

public enum MemosError: Error, LocalizedError {
    case notConfigured
    case networkError(Error)
    case unauthorized
    case serverError(statusCode: Int, message: String)
    case decodingError(Error)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Memos server not configured"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .unauthorized: return "Invalid or expired PAT"
        case .serverError(let code, let msg): return "Server error \(code): \(msg)"
        case .decodingError(let e): return "Decoding error: \(e.localizedDescription)"
        }
    }
}
