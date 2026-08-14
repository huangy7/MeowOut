import Foundation

/// 基金实时数据模型（内存中，不持久化）
public struct FundInfo: Identifiable, Sendable {
    public var id: String { code }
    public let code: String
    public let name: String
    public let netValue: Double          // 上一交易日单位净值 (NAV)
    public let estimatedValue: Double?   // 盘中估算净值 (GSZ)
    public let changePercent: Double     // 估算涨跌幅% (GSZZL)，若无则降级为实际涨跌幅
    public let navChangePercent: Double  // 上一日实际涨跌幅% (NAVCHGRT)
    public let updateTime: String
    public let netValueDate: String
    public let isRealTime: Bool          // 是否为盘中实时估算

    public init(
        code: String,
        name: String,
        netValue: Double,
        estimatedValue: Double?,
        changePercent: Double,
        navChangePercent: Double,
        updateTime: String,
        netValueDate: String,
        isRealTime: Bool = true
    ) {
        self.code = code
        self.name = name
        self.netValue = netValue
        self.estimatedValue = estimatedValue
        self.changePercent = changePercent
        self.navChangePercent = navChangePercent
        self.updateTime = updateTime
        self.netValueDate = netValueDate
        self.isRealTime = isRealTime
    }

    /// 当前最新实时净值（优先取盘中估算净值，无则取上一交易日净值）
    public var currentNav: Double {
        if let gsz = estimatedValue, gsz > 0 {
            return gsz
        }
        return netValue
    }

    /// 盘中估算收益
    public func estimatedGain(shares: Double) -> Double {
        guard shares > 0 else { return 0 }
        if let gsz = estimatedValue, gsz > 0, changePercent != 0 {
            let baseNav = gsz / (1 + changePercent / 100)
            return (gsz - baseNav) * shares
        }
        return netValue * shares * changePercent / 100
    }

    /// 当前持有市值
    public func holdingAmount(shares: Double) -> Double {
        guard shares > 0 else { return 0 }
        return currentNav * shares
    }

    /// 实时持有收益（纳入今日盘中实时波动）
    public func holdingGain(shares: Double, costPrice: Double) -> Double {
        guard shares > 0, costPrice > 0 else { return 0 }
        return (currentNav - costPrice) * shares
    }

    /// 实时持有收益率%
    public func holdingGainRate(costPrice: Double) -> Double {
        guard costPrice > 0 else { return 0 }
        return (currentNav - costPrice) / costPrice * 100
    }
}

/// 基金搜索结果
public struct FundSearchResult: Identifiable, Sendable {
    public var id: String { code }
    public let code: String
    public let name: String
    public let type: String
}
