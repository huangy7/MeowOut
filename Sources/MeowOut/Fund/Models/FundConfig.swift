import Foundation

public struct FundConfig: Codable, Identifiable, Sendable {
    public var id: String { code }
    public let code: String
    public var shares: Double
    public var costPrice: Double

    public init(code: String, shares: Double = 0, costPrice: Double = 0) {
        self.code = code
        self.shares = shares
        self.costPrice = costPrice
    }
}

@MainActor
public final class FundConfigStore: ObservableObject {
    public static let shared = FundConfigStore()

    private let userDefaultsKey = "fund.configs"

    @Published public var configs: [FundConfig] = []

    private init() {
        load()
    }

    public func load() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([FundConfig].self, from: data) else {
            configs = []
            return
        }
        configs = decoded
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    public func add(_ config: FundConfig) {
        guard !configs.contains(where: { $0.code == config.code }) else { return }
        configs.append(config)
        save()
    }

    public func remove(code: String) {
        configs.removeAll { $0.code == code }
        save()
        FundService.shared.removeFundFromCache(code: code)
    }

    public func update(code: String, shares: Double?, costPrice: Double?) {
        guard let index = configs.firstIndex(where: { $0.code == code }) else { return }
        if let shares = shares { configs[index].shares = shares }
        if let costPrice = costPrice { configs[index].costPrice = costPrice }
        save()
    }

    public func move(from source: IndexSet, to destination: Int) {
        configs.move(fromOffsets: source, toOffset: destination)
        save()
        FundService.shared.reorderFunds(by: configs.map(\.code))
    }

    public func moveUp(code: String) {
        guard let index = configs.firstIndex(where: { $0.code == code }), index > 0 else { return }
        configs.swapAt(index, index - 1)
        save()
        FundService.shared.reorderFunds(by: configs.map(\.code))
    }

    public func moveDown(code: String) {
        guard let index = configs.firstIndex(where: { $0.code == code }), index < configs.count - 1 else { return }
        configs.swapAt(index, index + 1)
        save()
        FundService.shared.reorderFunds(by: configs.map(\.code))
    }

    public var codeList: String {
        configs.map(\.code).joined(separator: ",")
    }

    // MARK: - Export & Import

    public func exportToJSONString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(configs),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    public enum ImportMode: Sendable {
        case replace // 覆盖现有列表
        case merge   // 合并追加（已存在的更新份额与成本，不存在的追加）
    }

    public static func parseConfigs(from jsonString: String) -> [FundConfig]? {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([FundConfig].self, from: data),
              !decoded.isEmpty else {
            return nil
        }

        var validConfigs: [FundConfig] = []
        var seenCodes = Set<String>()
        for cfg in decoded {
            let code = cfg.code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty, !seenCodes.contains(code) else { continue }
            seenCodes.insert(code)
            validConfigs.append(FundConfig(code: code, shares: max(0, cfg.shares), costPrice: max(0, cfg.costPrice)))
        }

        return validConfigs.isEmpty ? nil : validConfigs
    }

    @discardableResult
    public func importConfigs(_ validConfigs: [FundConfig], mode: ImportMode = .replace) -> Int {
        guard !validConfigs.isEmpty else { return 0 }

        switch mode {
        case .replace:
            configs = validConfigs
        case .merge:
            for newCfg in validConfigs {
                if let index = configs.firstIndex(where: { $0.code == newCfg.code }) {
                    configs[index].shares = newCfg.shares
                    configs[index].costPrice = newCfg.costPrice
                } else {
                    configs.append(newCfg)
                }
            }
        }

        save()
        Task { await FundService.shared.refresh() }
        return validConfigs.count
    }
}
