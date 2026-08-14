import Foundation
import Combine

@MainActor
public final class FundService: ObservableObject {
    public static let shared = FundService()

    @Published public private(set) var funds: [FundInfo] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastUpdateTime: Date?

    private var timer: AnyCancellable?
    private let configStore = FundConfigStore.shared
    private let settings = FundSettings.shared
    private var settingsCancellable: AnyCancellable?

    private let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration)
    }()

    private init() {}

    // MARK: - Lifecycle

    public func start() {
        settingsCancellable = settings.$refreshInterval
            .removeDuplicates()
            .sink { [weak self] interval in
                self?.restartTimer(interval: interval)
            }
        Task { await refresh() }
        restartTimer(interval: settings.refreshInterval)
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        settingsCancellable?.cancel()
        settingsCancellable = nil
    }

    // MARK: - Timer

    private func restartTimer(interval: Int) {
        timer?.cancel()
        guard interval > 0 else { return }
        let effectiveInterval = max(interval, 5)
        timer = Timer.publish(every: Double(effectiveInterval), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isTradeTime() else { return }
                Task { await self.refresh() }
            }
    }

    /// 判断当前是否在 A 股交易时段（北京时间 9:30-11:30, 13:00-15:00，工作日）
    private func isTradeTime() -> Bool {
        let beijing = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar.current
        calendar.timeZone = beijing

        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        guard weekday >= 2 && weekday <= 6 else { return false }

        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let timeValue = hour * 60 + minute

        let morningOpen = 9 * 60 + 30
        let morningClose = 11 * 60 + 30
        let afternoonOpen = 13 * 60
        let afternoonClose = 15 * 60

        return (timeValue >= morningOpen && timeValue <= morningClose) ||
               (timeValue >= afternoonOpen && timeValue <= afternoonClose)
    }

    // MARK: - Refresh Logic

    public func refresh() async {
        let configs = configStore.configs
        guard !configs.isEmpty else {
            funds = []
            lastError = nil
            return
        }

        isLoading = true
        lastError = nil

        let codeList = configs.map(\.code)
        let commaCodes = codeList.joined(separator: ",")

        // 1. 并发获取基础数据 (东财) + 新浪实时估值
        async let basicDataTask = fetchBasicInfo(codes: commaCodes)
        async let sinaDataTask = fetchSinaBatch(codes: codeList)

        let basicDict = (try? await basicDataTask) ?? [:]
        let sinaDict = await sinaDataTask

        // 2. 对于新浪未能覆盖的基金，使用天天基金接口进行兜底
        let missingSinaCodes = codeList.filter { sinaDict[$0] == nil }
        var ttValuations: [String: (name: String, gsz: Double?, gszzl: Double?, time: String, nav: Double?, pdate: String)] = [:]
        if !missingSinaCodes.isEmpty {
            ttValuations = (try? await fetchEstimation(codes: missingSinaCodes.joined(separator: ","))) ?? [:]
        }

        // 3. 校验是否有任何 API 成功返回有效数据
        let hasAnyResponse = !basicDict.isEmpty || !sinaDict.isEmpty || !ttValuations.isEmpty

        var merged: [FundInfo] = []
        for code in codeList {
            let basic = basicDict[code]
            let sina = sinaDict[code]
            let tt = ttValuations[code]
            let existing = self.funds.first(where: { $0.code == code })

            // 如果该基金所有接口均未返回任何数据且有旧缓存，保留旧数据
            if basic == nil && sina == nil && tt == nil, let existing = existing {
                merged.append(existing)
                continue
            }

            let fundName: String
            if let bName = basic?.name, !bName.isEmpty {
                fundName = bName
            } else if let ttName = tt?.name, !ttName.isEmpty {
                fundName = ttName
            } else if let eName = existing?.name, !eName.isEmpty && eName != code {
                fundName = eName
            } else {
                fundName = code
            }

            let netValue: Double
            if let bNav = basic?.nav, bNav > 0 {
                netValue = bNav
            } else if let ttNav = tt?.nav, ttNav > 0 {
                netValue = ttNav
            } else if let sinaGsz = sina?.gsz, sinaGsz > 0 {
                netValue = sinaGsz
            } else if let eNav = existing?.netValue, eNav > 0 {
                netValue = eNav
            } else {
                netValue = 0
            }

            let navChgRt = basic?.navChangePercent ?? existing?.navChangePercent ?? 0
            let pdate = basic?.pdate ?? tt?.pdate ?? existing?.netValueDate ?? ""

            if let sina = sina {
                // 新浪实时估值优先
                merged.append(FundInfo(
                    code: code,
                    name: fundName,
                    netValue: netValue,
                    estimatedValue: sina.gsz,
                    changePercent: sina.gszzl,
                    navChangePercent: navChgRt,
                    updateTime: sina.time,
                    netValueDate: pdate,
                    isRealTime: true
                ))
            } else if let tt = tt, let gsz = tt.gsz, let gszzl = tt.gszzl {
                // 天天基金实时估值次之
                merged.append(FundInfo(
                    code: code,
                    name: fundName,
                    netValue: netValue,
                    estimatedValue: gsz,
                    changePercent: gszzl,
                    navChangePercent: navChgRt,
                    updateTime: tt.time,
                    netValueDate: pdate,
                    isRealTime: true
                ))
            } else if basic != nil || tt != nil {
                // 无盘中实时估值时，降级使用上一交易日净值与实际涨跌幅
                merged.append(FundInfo(
                    code: code,
                    name: fundName,
                    netValue: netValue,
                    estimatedValue: nil,
                    changePercent: navChgRt,
                    navChangePercent: navChgRt,
                    updateTime: pdate,
                    netValueDate: pdate,
                    isRealTime: false
                ))
            } else if let existing = existing {
                merged.append(existing)
            }
        }

        if hasAnyResponse && !merged.isEmpty {
            funds = merged
            lastUpdateTime = Date()
            lastError = nil
        } else if funds.isEmpty {
            lastError = "网络请求失败，请检查网络连接"
        }

        isLoading = false
    }

    // MARK: - EastMoney Basic Info API

    private struct BasicFundMeta {
        let code: String
        let name: String
        let nav: Double
        let navChangePercent: Double
        let pdate: String
    }

    private func fetchBasicInfo(codes: String) async throws -> [String: BasicFundMeta] {
        let urlString = "https://fundmobapi.eastmoney.com/FundMNewApi/FundMNFInfo?pageIndex=1&pageSize=200&plat=Android&appType=ttjj&product=EFund&Version=1&deviceid=meowout&Fcodes=\(codes)"
        guard let url = URL(string: urlString) else { throw FundError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, _) = try await urlSession.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = (json["Datas"] ?? json["data"]) as? [[String: Any]] else {
            return [:]
        }

        var map: [String: BasicFundMeta] = [:]
        for item in dataDict {
            guard let code = item["FCODE"] as? String else { continue }
            let name = item["SHORTNAME"] as? String ?? code
            let nav = Self.parseDouble(item["NAV"]) ?? 0
            let navChgRt = Self.parseDouble(item["NAVCHGRT"]) ?? 0
            let pdate = item["PDATE"] as? String ?? ""
            map[code] = BasicFundMeta(code: code, name: name, nav: nav, navChangePercent: navChgRt, pdate: pdate)
        }
        return map
    }

    // MARK: - Sina Live Estimation API

    private struct SinaValuation {
        let gsz: Double
        let gszzl: Double
        let time: String
    }

    private func fetchSinaBatch(codes: [String]) async -> [String: SinaValuation] {
        await withTaskGroup(of: (String, SinaValuation?).self) { group in
            for code in codes {
                group.addTask {
                    let result = await self.fetchSingleSinaValuation(code: code)
                    return (code, result)
                }
            }

            var dict: [String: SinaValuation] = [:]
            for await (code, val) in group {
                if let val = val {
                    dict[code] = val
                }
            }
            return dict
        }
    }

    private func fetchSingleSinaValuation(code: String) async -> SinaValuation? {
        let urlString = "https://stock.finance.sina.com.cn/fundInfo/api/openapi.php/FdFundService.getEstimateNetworthPic?symbol=\(code)"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("https://finance.sina.com.cn/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 8

        do {
            let (data, _) = try await urlSession.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? [String: Any],
                  let status = result["status"] as? [String: Any] else {
                return nil
            }
            let statusCode = (status["code"] as? Int) ?? (status["code"] as? NSNumber)?.intValue ?? -1
            guard statusCode == 0 else {
                return nil
            }
            guard let resData = result["data"] as? [String: Any],
                  let networthArr = resData["networth"] as? [[String: Any]],
                  !networthArr.isEmpty else {
                return nil
            }

            // 过滤 15:00 之后的平直填充数据
            let timeRange = resData["time_range"] as? [[Any]]
            let closeTime = (timeRange?.count ?? 0) > 1 ? (timeRange?[1][1] as? String ?? "15:00") : "15:00"
            let closeTimeFull = "\(closeTime):00"

            var latestIdx = networthArr.count - 1
            while latestIdx > 0, let minTime = networthArr[latestIdx]["min_time"] as? String, minTime > closeTimeFull {
                latestIdx -= 1
            }

            let latest = networthArr[latestIdx]
            let rawPct = latest["nav2_pct"] ?? latest["nav_pct"]
            let rawNav = latest["pre_nav2"] ?? latest["pre_nav"] ?? resData["worth"]

            guard let gszzl = Self.parseDouble(rawPct),
                  let gsz = Self.parseDouble(rawNav) else {
                return nil
            }

            let minTime = (latest["min_time"] as? String)?.prefix(5) ?? ""
            let timeStr = minTime.isEmpty ? closeTime : String(minTime)

            return SinaValuation(gsz: gsz, gszzl: gszzl, time: timeStr)
        } catch {
            return nil
        }
    }

    // MARK: - Tiantian Valuation API (Backup)

    private func fetchEstimation(codes: String) async throws -> [String: (name: String, gsz: Double?, gszzl: Double?, time: String, nav: Double?, pdate: String)] {
        let urlString = "https://fundcomapi.tiantianfunds.com/mm/newCore/FundValuationLast?FCODES=\(codes)&FIELDS=FCODE,SHORTNAME,GSZZL,GZTIME,GSZ,NAV,PDATE"
        guard let url = URL(string: urlString) else { throw FundError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, _) = try await urlSession.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = (json["data"] ?? json["Datas"]) as? [[String: Any]] else {
            return [:]
        }

        var map: [String: (name: String, gsz: Double?, gszzl: Double?, time: String, nav: Double?, pdate: String)] = [:]
        for item in dataDict {
            guard let code = item["FCODE"] as? String else { continue }
            let name = item["SHORTNAME"] as? String ?? code
            let gsz = Self.parseDouble(item["GSZ"])
            let gszzl = Self.parseDouble(item["GSZZL"])
            let nav = Self.parseDouble(item["NAV"])
            let gztime = item["GZTIME"] as? String ?? ""
            let pdate = item["PDATE"] as? String ?? ""
            map[code] = (name, gsz, gszzl, gztime, nav, pdate)
        }
        return map
    }

    public func removeFundFromCache(code: String) {
        funds.removeAll { $0.code == code }
    }

    public func reorderFunds(by codeOrder: [String]) {
        funds = funds.sorted { a, b in
            let ia = codeOrder.firstIndex(of: a.code) ?? Int.max
            let ib = codeOrder.firstIndex(of: b.code) ?? Int.max
            return ia < ib
        }
    }

    // MARK: - Fund Search

    public func search(keyword: String) async -> [FundSearchResult] {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let urlString = "https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx?m=9&key=\(encoded)"
        guard let url = URL(string: urlString) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (data, _) = try await urlSession.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let datas = (json["Datas"] ?? json["data"]) as? [[String: Any]] else { return [] }
            return datas.compactMap { item -> FundSearchResult? in
                guard let code = item["CODE"] as? String,
                      let name = item["NAME"] as? String else { return nil }
                var type = ""
                if let baseInfo = item["FundBaseInfo"] as? [String: Any] {
                    type = baseInfo["FTYPE"] as? String ?? ""
                } else if let typeStr = item["FundBaseInfo"] as? String {
                    type = typeStr
                }
                return FundSearchResult(code: code, name: name, type: type)
            }
        } catch {
            return []
        }
    }

    // MARK: - Helper

    private static func parseDouble(_ value: Any?) -> Double? {
        if let num = value as? Double { return num }
        if let str = value as? String { return Double(str) }
        if let num = value as? NSNumber { return num.doubleValue }
        return nil
    }
}

public enum FundError: LocalizedError {
    case invalidURL
    case parseError

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的请求地址"
        case .parseError: return "数据解析失败"
        }
    }
}
