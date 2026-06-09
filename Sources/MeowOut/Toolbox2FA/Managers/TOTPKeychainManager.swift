import Foundation
import MemosKit

public enum TOTPKeychainManager {
    private static let service = "com.meowout.toolbox2fa"
    private static let account = "totp_vault"
    
    public static func save(accounts: [TOTPAccount]) async throws {
        let data = try JSONEncoder().encode(accounts)
        try await Task {
            try Task.checkCancellation()
            try KeychainService.save(data: data, service: service, account: account)
        }.value
    }
    
    public static func load() async throws -> [TOTPAccount] {
        try await Task {
            try Task.checkCancellation()
            do {
                let data = try KeychainService.load(service: service, account: account)
                return try JSONDecoder().decode([TOTPAccount].self, from: data)
            } catch KeychainService.KeychainError.notFound {
                return []
            }
        }.value
    }
}
