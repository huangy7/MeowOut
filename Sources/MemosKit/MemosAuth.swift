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
        UserDefaults.standard.set(baseURL.absoluteString, forKey: baseURLKey)
        try writeKeychain(pat)
    }

    public func clear() {
        UserDefaults.standard.removeObject(forKey: baseURLKey)
        deleteKeychain()
    }

    // MARK: - Keychain

    private func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeKeychain(_ value: String) throws {
        deleteKeychain()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: value.data(using: .utf8)!
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw MemosError.networkError(
                NSError(domain: NSOSStatusErrorDomain, code: Int(status)))
        }
    }

    private func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}
