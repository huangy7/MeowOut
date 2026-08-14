import Foundation
import Combine

@MainActor
public final class FundPanelViewModel: ObservableObject {
    @Published public var isPrivacyMode: Bool = false

    private let service = FundService.shared
    private let configStore = FundConfigStore.shared
    private let settings = FundSettings.shared
    private var cancellables = Set<AnyCancellable>()

    public init() {
        isPrivacyMode = settings.privacyMode

        service.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        configStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        settings.$privacyMode
            .sink { [weak self] mode in self?.isPrivacyMode = mode }
            .store(in: &cancellables)
    }

    // MARK: - Data Accessors

    public var funds: [FundInfo] { service.funds }
    public var isLoading: Bool { service.isLoading }
    public var lastError: String? { service.lastError }
    public var lastUpdateTime: Date? { service.lastUpdateTime }

    public func config(for code: String) -> FundConfig? {
        configStore.configs.first(where: { $0.code == code })
    }

    // MARK: - Computed Aggregates

    public var totalAssets: Double {
        funds.reduce(0) { sum, fund in
            let shares = config(for: fund.code)?.shares ?? 0
            return sum + fund.holdingAmount(shares: shares)
        }
    }

    public var totalCost: Double {
        funds.reduce(0) { sum, fund in
            let cfg = config(for: fund.code)
            let shares = cfg?.shares ?? 0
            let cost = cfg?.costPrice ?? 0
            guard shares > 0, cost > 0 else { return sum }
            return sum + (cost * shares)
        }
    }

    public var dailyEstimatedGain: Double {
        funds.reduce(0) { sum, fund in
            let shares = config(for: fund.code)?.shares ?? 0
            return sum + fund.estimatedGain(shares: shares)
        }
    }

    public var dailyGainRate: Double {
        let baseAssets = totalAssets - dailyEstimatedGain
        guard baseAssets > 0 else { return 0 }
        return (dailyEstimatedGain / baseAssets) * 100
    }

    public var holdingGain: Double {
        funds.reduce(0) { sum, fund in
            let cfg = config(for: fund.code)
            let shares = cfg?.shares ?? 0
            let cost = cfg?.costPrice ?? 0
            return sum + fund.holdingGain(shares: shares, costPrice: cost)
        }
    }

    public var totalHoldingGainRate: Double {
        guard totalCost > 0 else { return 0 }
        return (holdingGain / totalCost) * 100
    }

    // MARK: - Actions

    public func refresh() async {
        await service.refresh()
    }

    public func togglePrivacy() {
        isPrivacyMode.toggle()
    }

    public func reset() {
        isPrivacyMode = settings.privacyMode
    }

    public var formattedUpdateTime: String {
        guard let time = lastUpdateTime else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter.string(from: time)
    }
}
