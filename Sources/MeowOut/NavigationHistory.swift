// Sources/MeowOut/NavigationHistory.swift
import Foundation

/// 通用的导航历史栈：一条路由序列加一个游标，供侧栏式窗口的「前进 / 后退」使用。
/// 与具体窗口无关，任何需要钻取式导航的窗口都可以用自己的路由类型实例化。
struct NavigationHistory<Route: Hashable> {
    private(set) var routes: [Route]
    private(set) var cursor: Int

    init(root: Route) {
        routes = [root]
        cursor = 0
    }

    var current: Route { routes[cursor] }
    var canGoBack: Bool { cursor > 0 }
    var canGoForward: Bool { cursor < routes.count - 1 }

    /// 压入一条新路由。
    /// 与当前路由相同时直接忽略：反复点击同一个侧栏页签不会把历史撑成同一条记录的重复串，
    /// 也就保证了「后退」永远指向一个真正不同的页面。
    /// 其余情况下丢弃游标之后的前进分支，这是浏览器与系统设置共有的语义。
    mutating func push(_ route: Route) {
        guard route != current else { return }
        routes.removeSubrange((cursor + 1)...)
        routes.append(route)
        cursor = routes.count - 1
    }

    mutating func goBack() {
        guard canGoBack else { return }
        cursor -= 1
    }

    mutating func goForward() {
        guard canGoForward else { return }
        cursor += 1
    }
}

/// 设置窗口的路由：一个侧栏页，或压栈进入的常用语列表页 / 单条常用语编辑页 / 统计页。
enum SettingsRoute: Hashable {
    case tab(String)
    case keydropManager
    case keydropManagerEntry(UUID)
    case statistics

    /// 钻进子页时父页签保持高亮，对齐系统设置里「通用 → 关于本机」的表现。
    var highlightedSidebarID: String {
        switch self {
        case .tab(let id): return id
        case .keydropManager, .keydropManagerEntry: return "keydrop"
        case .statistics: return "rest"
        }
    }
}
