import Foundation
import Security

public enum KeychainService {
    private static let lock = NSLock()

    public enum KeychainError: Error, LocalizedError {
        case notFound
        case operationFailed(status: OSStatus, message: String)

        public var errorDescription: String? {
            switch self {
            case .notFound:
                return "Keychain item not found"
            case .operationFailed(let status, let message):
                return "Keychain operation failed with status \(status): \(message)"
            }
        }
    }

    public static func save(data: Data, service: String, account: String? = nil) throws {
        lock.lock()
        defer { lock.unlock() }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if let account = account {
            query[kSecAttrAccount as String] = account
        }

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                let message = SecCopyErrorMessageString(addStatus, nil) as String? ?? "Unknown error"
                throw KeychainError.operationFailed(status: addStatus, message: message)
            }
        } else if status != errSecSuccess {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            throw KeychainError.operationFailed(status: status, message: message)
        }
    }

    public static func save(string: String, service: String, account: String? = nil) throws {
        guard let data = string.data(using: .utf8) else { return }
        try save(data: data, service: service, account: account)
    }

    public static func load(service: String, account: String? = nil) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let account = account {
            query[kSecAttrAccount as String] = account
        }

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return data
        } else if status == errSecItemNotFound {
            throw KeychainError.notFound
        } else {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            throw KeychainError.operationFailed(status: status, message: message)
        }
    }

    public static func loadString(service: String, account: String? = nil) throws -> String {
        let data = try load(service: service, account: account)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.operationFailed(status: -1, message: "Invalid string encoding")
        }
        return string
    }

    public static func delete(service: String, account: String? = nil) throws {
        lock.lock()
        defer { lock.unlock() }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if let account = account {
            query[kSecAttrAccount as String] = account
        }

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            throw KeychainError.operationFailed(status: status, message: message)
        }
    }
}
