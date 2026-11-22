// Sources/MeowOut/Settings/SettingsWindowResizeSupport.swift
import AppKit
import SwiftUI

/// 设置窗口按页签自适应扩宽/还原的纯几何计算：锚定左上角并限制在屏幕可见范围内。
struct SettingsWindowFrameCalculator {
    static let compactDefaultSize = CGSize(width: 660, height: 580)
    static let keyDropPreferredSize = CGSize(width: 860, height: 620)

    static func frameAnchoredTopLeft(
        current: CGRect,
        targetSize: CGSize,
        visibleScreenFrame: CGRect?
    ) -> CGRect {
        let clampedWidth: CGFloat
        let clampedHeight: CGFloat
        if let screen = visibleScreenFrame {
            clampedWidth = min(targetSize.width, screen.width)
            clampedHeight = min(targetSize.height, screen.height)
        } else {
            clampedWidth = targetSize.width
            clampedHeight = targetSize.height
        }

        // AppKit 坐标系原点位于左下角：固定 top = current.maxY 与 left = current.origin.x
        var originX = current.origin.x
        var originY = current.maxY - clampedHeight

        if let screen = visibleScreenFrame {
            if originX + clampedWidth > screen.maxX {
                originX = max(screen.minX, screen.maxX - clampedWidth)
            }
            if originX < screen.minX {
                originX = screen.minX
            }
            if originY < screen.minY {
                originY = screen.minY
            }
            if originY + clampedHeight > screen.maxY {
                originY = screen.maxY - clampedHeight
            }
        }

        return CGRect(x: originX, y: originY, width: clampedWidth, height: clampedHeight)
    }
}

/// 轻量桥接视图：获取设置窗口所属 NSWindow，在进入/离开「常用语」双栏工作台时平滑扩宽与还原。
struct SettingsWindowResizeBridge: NSViewRepresentable {
    static let compactAutosaveName = "MeowOutSettingsWindowV2"

    let isExpandedWorkspace: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.sync(window: window, isExpanded: isExpandedWorkspace, animated: false)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                context.coordinator.sync(window: window, isExpanded: isExpandedWorkspace, animated: true)
            }
        }
    }

    @MainActor
    final class Coordinator {
        private var lastExpandedState: Bool?
        private var compactSizeBeforeExpand: CGSize?
        private var preferredExpandedSize: CGSize = SettingsWindowFrameCalculator.keyDropPreferredSize

        func sync(window: NSWindow, isExpanded: Bool, animated: Bool) {
            if lastExpandedState == nil {
                lastExpandedState = isExpanded
                if isExpanded {
                    expand(window: window, animated: animated)
                }
                return
            }

            guard lastExpandedState != isExpanded else { return }
            lastExpandedState = isExpanded

            if isExpanded {
                expand(window: window, animated: animated)
            } else {
                restoreCompact(window: window, animated: animated)
            }
        }

        private func expand(window: NSWindow, animated: Bool) {
            let current = window.frame
            if compactSizeBeforeExpand == nil {
                compactSizeBeforeExpand = current.size
            }
            // 临时暂停 autosave，避免在常用语页关窗时把扩宽后的尺寸写回常规紧凑默认尺寸
            window.setFrameAutosaveName("")

            let targetSize = CGSize(
                width: max(current.width, preferredExpandedSize.width),
                height: max(current.height, preferredExpandedSize.height)
            )
            let targetFrame = SettingsWindowFrameCalculator.frameAnchoredTopLeft(
                current: current,
                targetSize: targetSize,
                visibleScreenFrame: window.screen?.visibleFrame
            )
            if abs(targetFrame.width - current.width) > 1 || abs(targetFrame.height - current.height) > 1 {
                window.setFrame(targetFrame, display: true, animate: animated)
            }
        }

        private func restoreCompact(window: NSWindow, animated: Bool) {
            let current = window.frame
            // 记住用户在常用语页手动拉宽过的尺寸（同一会话内切回时沿用）
            if current.width >= SettingsWindowFrameCalculator.keyDropPreferredSize.width {
                preferredExpandedSize = current.size
            }

            if let compactSize = compactSizeBeforeExpand {
                let targetFrame = SettingsWindowFrameCalculator.frameAnchoredTopLeft(
                    current: current,
                    targetSize: compactSize,
                    visibleScreenFrame: window.screen?.visibleFrame
                )
                if abs(targetFrame.width - current.width) > 1 || abs(targetFrame.height - current.height) > 1 {
                    window.setFrame(targetFrame, display: true, animate: animated)
                }
                compactSizeBeforeExpand = nil
            }
            window.setFrameAutosaveName(SettingsWindowResizeBridge.compactAutosaveName)
        }
    }
}
