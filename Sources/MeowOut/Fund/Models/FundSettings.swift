import Foundation

@MainActor
public final class FundSettings: ObservableObject {
    public static let shared = FundSettings()

    @Published public var refreshInterval: Int {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "fund.settings.refreshInterval") }
    }

    @Published public var privacyMode: Bool {
        didSet { UserDefaults.standard.set(privacyMode, forKey: "fund.settings.privacyMode") }
    }

    private init() {
        let savedInterval = UserDefaults.standard.integer(forKey: "fund.settings.refreshInterval")
        self.refreshInterval = savedInterval > 0 ? savedInterval : 30
        self.privacyMode = UserDefaults.standard.bool(forKey: "fund.settings.privacyMode")
    }
}
