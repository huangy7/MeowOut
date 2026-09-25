// Tests/MeowOutTests/NavigationHistoryTests.swift
import XCTest
@testable import MeowOut

final class NavigationHistoryTests: XCTestCase {

    func testInitialStateHasNoHistory() {
        let history = NavigationHistory(root: SettingsRoute.tab("rest"))
        XCTAssertEqual(history.current, .tab("rest"))
        XCTAssertFalse(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }

    func testPushThenGoBackAndForward() {
        var history = NavigationHistory(root: SettingsRoute.tab("rest"))
        history.push(.tab("keydrop"))

        XCTAssertEqual(history.current, .tab("keydrop"))
        XCTAssertTrue(history.canGoBack)
        XCTAssertFalse(history.canGoForward)

        history.goBack()
        XCTAssertEqual(history.current, .tab("rest"))
        XCTAssertTrue(history.canGoForward)

        history.goForward()
        XCTAssertEqual(history.current, .tab("keydrop"))
    }

    func testPushingSameRouteDoesNotAppend() {
        var history = NavigationHistory(root: SettingsRoute.tab("rest"))
        history.push(.tab("rest"))

        // 反复点击同一个侧栏页签不应产生历史记录，否则「后退」会原地踏步
        XCTAssertFalse(history.canGoBack)
        XCTAssertEqual(history.current, .tab("rest"))
    }

    func testPushAfterGoBackTruncatesForwardBranch() {
        var history = NavigationHistory(root: SettingsRoute.tab("rest"))
        history.push(.tab("keydrop"))
        history.push(.keydropManager)
        history.goBack()                    // 游标回到 .tab("keydrop")
        history.push(.tab("memos"))         // 分支：丢弃 .keydropManager

        XCTAssertEqual(history.current, .tab("memos"))
        XCTAssertFalse(history.canGoForward)

        history.goBack()
        XCTAssertEqual(history.current, .tab("keydrop"))
        history.goBack()
        XCTAssertEqual(history.current, .tab("rest"))
        XCTAssertFalse(history.canGoBack)
    }

    func testGoBackAndForwardDoNotOverrunBounds() {
        var history = NavigationHistory(root: SettingsRoute.tab("rest"))
        history.goBack()
        history.goBack()
        XCTAssertEqual(history.current, .tab("rest"))

        history.push(.keydropManager)
        history.goForward()
        history.goForward()
        XCTAssertEqual(history.current, .keydropManager)
    }

    func testKeydropManagerHighlightsKeydropSidebarItem() {
        XCTAssertEqual(SettingsRoute.keydropManager.highlightedSidebarID, "keydrop")
        XCTAssertEqual(SettingsRoute.tab("memos").highlightedSidebarID, "memos")
    }

    func testKeydropManagerEntryHighlightsKeydropSidebarItem() {
        XCTAssertEqual(SettingsRoute.keydropManagerEntry(UUID()).highlightedSidebarID, "keydrop")
    }

    func testDifferentKeydropEntriesAreDistinctRoutes() {
        let first = UUID()
        let second = UUID()
        XCTAssertNotEqual(SettingsRoute.keydropManagerEntry(first),
                          SettingsRoute.keydropManagerEntry(second))

        var history = NavigationHistory(root: SettingsRoute.keydropManager)
        history.push(.keydropManagerEntry(first))
        history.push(.keydropManagerEntry(second))
        history.goBack()
        XCTAssertEqual(history.current, .keydropManagerEntry(first))
    }

    func testPushingSameEntryTwiceDoesNotGrowHistory() {
        // 列表用 List(selection:) + onChange 推进，macOS 14 上选中绑定每次点击会触发两次。
        // 等值去重保证第二次是 no-op，否则一次点击会压两条历史。
        let id = UUID()
        var history = NavigationHistory(root: SettingsRoute.keydropManager)
        history.push(.keydropManagerEntry(id))
        history.push(.keydropManagerEntry(id))

        history.goBack()
        XCTAssertEqual(history.current, .keydropManager)
        XCTAssertFalse(history.canGoBack)
    }

    func testBrowseStateDefaultsToUnfilteredList() {
        // 两个默认值都是承重的：分类默认「全部」列表才会以未筛选的状态打开，
        // 搜索默认空串才不会一进列表就是空结果。
        let browse = KeyDropBrowseState()
        XCTAssertEqual(browse.selectedCategory, KeyDropConstants.categoryAll)
        XCTAssertEqual(browse.searchText, "")
    }

    func testStatisticsHighlightsHealthSidebarItem() {
        // 统计从「健康作息」推进进入，所以侧栏要停在高亮那一项上
        XCTAssertEqual(SettingsRoute.statistics.highlightedSidebarID, "rest")
    }

    func testStatisticsIsDistinctFromItsParentTab() {
        var history = NavigationHistory(root: SettingsRoute.tab("rest"))
        history.push(.statistics)
        XCTAssertEqual(history.current, .statistics)

        history.goBack()
        XCTAssertEqual(history.current, .tab("rest"))
    }
}
