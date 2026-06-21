import AppKit

public final class ClipboardImageCache: @unchecked Sendable {
    public static let shared = ClipboardImageCache()
    private let cache = NSCache<NSString, NSImage>()
    
    private init() {
        cache.countLimit = 50
    }
    
    public func getImage(forKey key: String) -> NSImage? {
        return cache.object(forKey: key as NSString)
    }
    
    public func setImage(_ image: NSImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
    
    public func clear() {
        cache.removeAllObjects()
    }
}
