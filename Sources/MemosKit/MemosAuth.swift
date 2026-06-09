import Foundation
import Security

public class MemosAuth: @unchecked Sendable {
    public static let shared = MemosAuth()

    private let service: String
    private let baseURLKey: String

    public init(service: String = "com.meowout.memos", baseURLKey: String = "memosBaseURL") {
        self.service = service
        self.baseURLKey = baseURLKey
    }

    public var baseURL: URL? {
        get {
            guard let s = UserDefaults.standard.string(forKey: baseURLKey) else { return nil }
            return URL(string: s)
        }
    }

    public var pat: String? {
        get { readKeychain() }
    }

    public var isConfigured: Bool {
        baseURL != nil && pat != nil
    }

    public func configure(baseURL: URL, pat: String) throws {
        try writeKeychain(pat)
        UserDefaults.standard.set(baseURL.absoluteString, forKey: baseURLKey)
    }

    public func clear() {
        UserDefaults.standard.removeObject(forKey: baseURLKey)
        deleteKeychain()
    }

    // MARK: - Keychain

    private func readKeychain() -> String? {
        do {
            return try KeychainService.loadString(service: service)
        } catch {
            return nil
        }
    }

    private func writeKeychain(_ value: String) throws {
        try KeychainService.save(string: value, service: service)
    }

    private func deleteKeychain() {
        try? KeychainService.delete(service: service)
    }
}
