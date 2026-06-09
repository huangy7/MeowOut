import Foundation
import SwiftOTP
#if canImport(AppKit)
import AppKit
#endif

public struct TOTPCodeInfo {
    public let code: String
    public let progress: Double // 0.0 to 1.0 (approaching expiration)
}

@MainActor
public class TOTPGenerator: ObservableObject {
    public static let shared = TOTPGenerator()
    
    @Published public var accounts: [TOTPAccount] = []
    @Published public var currentCodes: [String: TOTPCodeInfo] = [:]
    
    private var timer: Timer?
    private var didBecomeActiveObserver: NSObjectProtocol?
    
    private init() {
        startTimer()
        Task {
            try? await loadAccounts()
        }
    }
    
    public func loadAccounts() async throws {
        accounts = try await TOTPKeychainManager.load()
        refreshCodes()
    }
    
    public func saveAccounts() async throws {
        try await TOTPKeychainManager.save(accounts: accounts)
        refreshCodes()
    }
    
    public func addAccount(_ account: TOTPAccount) async throws {
        let newAccounts = accounts + [account]
        try await TOTPKeychainManager.save(accounts: newAccounts)
        accounts = newAccounts
        refreshCodes()
    }
    
    public func addAccounts(_ newAccounts: [TOTPAccount]) async throws {
        let updatedAccounts = accounts + newAccounts
        try await TOTPKeychainManager.save(accounts: updatedAccounts)
        accounts = updatedAccounts
        refreshCodes()
    }
    
    public func updateAccount(_ account: TOTPAccount) async throws {
        if let idx = accounts.firstIndex(where: { $0.uuid == account.uuid }) {
            var newAccounts = accounts
            newAccounts[idx] = account
            try await TOTPKeychainManager.save(accounts: newAccounts)
            accounts = newAccounts
            refreshCodes()
        }
    }
    
    public func deleteAccount(withId uuid: String) async throws {
        let newAccounts = accounts.filter { $0.uuid != uuid }
        try await TOTPKeychainManager.save(accounts: newAccounts)
        accounts = newAccounts
        refreshCodes()
    }
    
    public func moveAccounts(fromOffsets source: IndexSet, toOffset destination: Int) async throws {
        var newAccounts = accounts
        newAccounts.move(fromOffsets: source, toOffset: destination)
        try await TOTPKeychainManager.save(accounts: newAccounts)
        accounts = newAccounts
        refreshCodes()
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshCodes()
            }
        }
#if canImport(AppKit)
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCodes()
            }
        }
#endif
    }
    
    deinit {
        timer?.invalidate()
#if canImport(AppKit)
        if let observer = didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
#endif
    }
    
    private func refreshCodes() {
        let time = Date()
        let timeInterval = time.timeIntervalSince1970
        
        var newCodes: [String: TOTPCodeInfo] = [:]
        
        for account in accounts {
            let alg: SwiftOTP.OTPAlgorithm
            switch account.algorithm {
            case .SHA256: alg = .sha256
            case .SHA512: alg = .sha512
            default: alg = .sha1
            }
            
            let rawPeriod = account.period ?? 30
            guard rawPeriod > 0 else { continue }
            let period = TimeInterval(rawPeriod)
            let remainder = timeInterval.truncatingRemainder(dividingBy: period)
            let progress = remainder / period
            
            let digits = account.digits ?? 6
            guard let secretData = base32DecodeToData(account.secret.filter { !$0.isWhitespace }),
                  let totp = TOTP(secret: secretData, digits: digits, timeInterval: Int(period), algorithm: alg) else {
                newCodes[account.uuid] = TOTPCodeInfo(code: "------", progress: progress)
                continue
            }
            if let code = totp.generate(time: time) {
                let formatted: String
                if code.count == 6 {
                    formatted = "\(code.prefix(3)) \(code.suffix(3))"
                } else if code.count == 8 {
                    formatted = "\(code.prefix(4)) \(code.suffix(4))"
                } else {
                    formatted = code
                }
                newCodes[account.uuid] = TOTPCodeInfo(code: formatted, progress: progress)
            } else {
                newCodes[account.uuid] = TOTPCodeInfo(code: "------", progress: progress)
            }
        }
        currentCodes = newCodes
    }
}
