import SwiftUI
import AppKit

private class BundleFinder {}

public struct BuiltInToolIconView: View {
    public let type: BuiltInToolType
    public var size: CGFloat = 32

    private static var iconCache: [BuiltInToolType: NSImage] = [:]
    private static let lock = NSLock()

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle(for: BundleFinder.self)
        #endif
    }

    public init(type: BuiltInToolType, size: CGFloat = 32) {
        self.type = type
        self.size = size
    }

    private var cornerRadius: CGFloat {
        size * (7.2 / 32.0)
    }

    public static func assetName(for type: BuiltInToolType) -> String {
        switch type {
        case .keepAwake: return "keepAwake"
        case .keyboardCleaning: return "keyboardCleaning"
        case .screenCleaning: return "screenCleaning"
        case .toolbox2FA: return "toolbox2FA"
        case .memosQuickCapture: return "memosQuickCapture"
        case .memosOpenBrowser: return "memosOpenBrowser"
        case .breathing: return "breathing"
        case .fund: return "fund"
        }
    }

    public static func loadAssetImage(for type: BuiltInToolType) -> NSImage? {
        lock.lock()
        if let cached = iconCache[type] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let name = assetName(for: type)
        let loadedImage: NSImage?
        let bundle = resourceBundle
        if let url = bundle.url(forResource: name, withExtension: "png") {
            loadedImage = NSImage(contentsOf: url)
        } else if let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "BuiltInIcons") {
            loadedImage = NSImage(contentsOf: url)
        } else {
            loadedImage = bundle.image(forResource: NSImage.Name(name))
                ?? NSImage(named: NSImage.Name(name))
        }

        if let image = loadedImage {
            lock.lock()
            iconCache[type] = image
            lock.unlock()
        }
        return loadedImage
    }

    public var body: some View {
        Group {
            if let nsImage = Self.loadAssetImage(for: type) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                fallbackView
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var fallbackView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(0.8))
            Text(type.icon)
                .font(.system(size: size * 0.5))
        }
    }
}
