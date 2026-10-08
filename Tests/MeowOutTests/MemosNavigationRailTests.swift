import AppKit
import SwiftUI
import XCTest
@testable import MeowOut

@MainActor
final class MemosNavigationRailTests: XCTestCase {
    /// 导航栏背景必须铺满父视图分给它的整列宽度。
    ///
    /// VStack 的固有宽度只有图标按钮的 44pt（列宽是 72pt），若只约束高度不约束宽度，
    /// 背景就只画中间 44pt，两侧各留一条父视图底色。窗口底色与导航栏底色一旦不同，
    /// 就会显示成一条被截断的窄条。
    func testBackgroundFillsFullColumnWidth() throws {
        let columnWidth: CGFloat = 72
        let rail = MemosNavigationRail(selectedPage: .constant(.memos))
            .frame(width: columnWidth, height: 200)

        let host = NSHostingView(rootView: rail)
        host.frame = NSRect(x: 0, y: 0, width: columnWidth, height: 200)
        host.layoutSubtreeIfNeeded()

        let rep = try XCTUnwrap(
            host.bitmapImageRepForCachingDisplay(in: host.bounds),
            "无法为导航栏创建位图"
        )
        host.cacheDisplay(in: host.bounds, to: rep)

        // 护栏：先确认离屏渲染确实产出了内容。x=36 落在 VStack 固有宽度（44pt）之内，
        // 无论背景是否铺满都应当是不透明的；这里若取不到不透明像素，说明渲染环境不可用，
        // 跳过而不是把环境问题误报成布局回归。
        let insideVStack = try XCTUnwrap(rep.colorAt(x: 36, y: 80), "取色失败")
        guard insideVStack.alphaComponent > 0 else {
            throw XCTSkip("导航栏离屏渲染不可用，跳过该断言")
        }

        // 图标按钮只占中间 44pt（x 14..58），x=4 落在两侧留白区，
        // 背景铺满时这里应当是不透明的导航栏底色，只铺 44pt 时则是透明。
        for sampleY in stride(from: 20, to: 180, by: 20) {
            let color = try XCTUnwrap(rep.colorAt(x: 4, y: sampleY), "取色失败 y=\(sampleY)")
            XCTAssertGreaterThan(
                color.alphaComponent, 0,
                "导航栏背景未铺满列宽：x=4 y=\(sampleY) 处仍是透明的"
            )
        }
    }
}
