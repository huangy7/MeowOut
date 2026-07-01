// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO

enum ImageThumbnailer {
    static let defaultPointSize: CGFloat = 20

    static func thumbnail(for url: URL, pointSize: CGFloat = defaultPointSize) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        let maxPixelSize = pixelSize(for: pointSize)
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let scale = backingScale
        let size = NSSize(width: CGFloat(cgImage.width) / scale,
                          height: CGFloat(cgImage.height) / scale)
        return NSImage(cgImage: cgImage, size: size)
    }

    static func thumbnail(for image: NSImage, pointSize: CGFloat = defaultPointSize) -> NSImage? {
        let pixels = pixelSize(for: pointSize)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pixels,
                                         pixelsHigh: pixels,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return nil
        }

        let logicalSize = NSSize(width: pointSize, height: pointSize)
        rep.size = logicalSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: logicalSize).fill()
        image.draw(in: NSRect(origin: .zero, size: logicalSize),
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1,
                   respectFlipped: false,
                   hints: nil)
        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: logicalSize)
        result.addRepresentation(rep)
        return result
    }

    static func estimatedBitmapCost(pointSize: CGFloat = defaultPointSize) -> Int {
        let pixels = pixelSize(for: pointSize)
        return pixels * pixels * 4
    }

    private static var backingScale: CGFloat {
        max(1, NSScreen.main?.backingScaleFactor ?? 2)
    }

    private static func pixelSize(for pointSize: CGFloat) -> Int {
        max(16, Int((pointSize * backingScale).rounded(.up)))
    }
}
