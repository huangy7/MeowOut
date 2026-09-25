import SwiftUI
import AppKit

/// 托盘图标渲染器：帧渲染/缓存纯逻辑类，由 MenuBarController 驱动。
@MainActor
final class TrayIconRenderer {
    private(set) var frameCache: [Int: NSImage] = [:]
    private(set) var staticCache: NSImage?

    private struct RenderKey: Equatable {
        let state: AppPhase
        let pet: AppState.PetType
        let useClassic: Bool
        let colorScheme: ColorScheme
    }
    private var lastKey: RenderKey?

    /// 是否播放走路动画。用户空闲（isWalking 为 false）或关闭了动画开关时都不播放，
    /// 固定展示静态帧。两处调用点共用这一个判据，避免各判一半而出现不一致。
    static func shouldAnimate(appState: AppState) -> Bool {
        appState.isWalking && appState.enableTrayPetAnimation
    }

    /// 当前应显示的图标（走路时取动画帧，否则取静态帧）
    func currentImage(appState: AppState) -> NSImage? {
        Self.shouldAnimate(appState: appState) ? frameCache[appState.currentFrameIndex] : staticCache
    }

    /// 状态/宠物/外观变化时重建缓存；返回 true 表示缓存被重建
    @discardableResult
    func refreshIfNeeded(appState: AppState, colorScheme: ColorScheme) -> Bool {
        let key = RenderKey(state: appState.currentState,
                            pet: appState.selectedPet,
                            useClassic: appState.useClassicTrayIcon,
                            colorScheme: colorScheme)
        guard key != lastKey || frameCache.isEmpty else { return false }
        prepare(appState: appState, colorScheme: colorScheme)
        lastKey = key
        return true
    }

    private func prepare(appState: AppState, colorScheme: ColorScheme) {
        let color = trayIconColor(for: appState.currentState)
        let state = appState.currentState
        let useClassic = appState.useClassicTrayIcon

        frameCache.removeAll()

        let isW = (state == .working || state == .alerting || state == .overworking)

        for i in 0..<5 {
            if useClassic {
                if let img = loadAndPrepareImage(name: "\(i)", color: color, isTemplate: (state == .working || state == .idle)) {
                    frameCache[i] = img
                }
            } else {
                frameCache[i] = renderPetCanvas(appState: appState,
                                                isWalking: isW,
                                                now: TimeInterval(i) * 0.2,
                                                colorScheme: colorScheme)
            }
        }

        // 静止帧单独按非行走姿态渲染：frame 0 是走路循环的第一帧，直接复用会让宠物
        // 停下来时定格在迈步姿势。「宠物行为」页的预览用的就是非行走姿态，两者应一致。
        // 经典图标模式只有走路帧的 PNG、没有对应静止帧，只能沿用 frame 0。
        staticCache = useClassic
            ? frameCache[0]
            : renderPetCanvas(appState: appState, isWalking: false, now: 0, colorScheme: colorScheme)

        #if DEBUG
        print("💾 Tray icon cache refreshed for state: \(state) pet: \(appState.selectedPet.rawValue) classic: \(useClassic)")
        #endif
    }

    /// 把当前宠物画布渲染成菜单栏图标
    private func renderPetCanvas(appState: AppState,
                                 isWalking: Bool,
                                 now: TimeInterval,
                                 colorScheme: ColorScheme) -> NSImage? {
        let canvas: AnyView = {
            switch appState.selectedPet {
            case .clawd: return AnyView(ClawdCanvasView(pose: .rest, height: 18, isWalking: isWalking, now: now))
            case .panda: return AnyView(PandaCanvasView(pose: .rest, height: 18, isWalking: isWalking, now: now))
            case .pika: return AnyView(PikaCanvasView(pose: .rest, height: 18, isWalking: isWalking, now: now))
            }
        }()

        // ImageRenderer 使用独立环境，显式传入当前外观模式
        let renderer = ImageRenderer(content: AnyView(canvas).environment(\.colorScheme, colorScheme))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0

        guard let cgImage = renderer.cgImage else { return nil }
        let logicalWidth = CGFloat(cgImage.width) / renderer.scale
        let image = NSImage(cgImage: cgImage, size: NSSize(width: logicalWidth, height: 18))
        image.isTemplate = false // 全彩像素
        return image
    }

    private func trayIconColor(for state: AppPhase) -> NSColor {
        switch state {
        case .working: return .black // Not used for tinting when isTemplate=true
        case .breathing: return .systemTeal
        case .alerting: return .orange
        case .resting: return .red
        case .overworking: return .red
        case .paused: return .lightGray
        case .idle: return .lightGray
        }
    }

    private func loadAndPrepareImage(name: String, color: NSColor, isTemplate: Bool) -> NSImage? {
        // In Xcode targets, images in xcassets are available via NSImage(named:)
        guard let image = NSImage(named: "RunningCat\(name)") else { return nil }

        let aspectRatio = image.size.width / image.size.height
        let targetHeight: CGFloat = 18.0
        let targetWidth = targetHeight * aspectRatio

        let resized = resizeImage(image, to: NSSize(width: targetWidth, height: targetHeight))

        if isTemplate {
            resized.isTemplate = true
            return resized
        } else {
            return tintNSImage(resized, with: color)
        }
    }

    private func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    private func tintNSImage(_ image: NSImage, with color: NSColor) -> NSImage {
        let tintedImage = NSImage(size: image.size)
        tintedImage.lockFocus()
        // Use a non-dynamic color space resolution just in case
        if let resolvedColor = color.usingColorSpace(.sRGB) {
            resolvedColor.set()
        } else {
            color.set()
        }
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill()
        image.draw(in: imageRect, from: NSRect(origin: .zero, size: image.size), operation: .destinationIn, fraction: 1.0)
        tintedImage.unlockFocus()
        tintedImage.isTemplate = false
        return tintedImage
    }
}
