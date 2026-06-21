import XCTest
import AppKit
@testable import MeowOut

final class ClipboardImageCacheTests: XCTestCase {
    func testCacheStorageAndRetrieval() {
        let cache = ClipboardImageCache.shared
        let image = NSImage(size: NSSize(width: 10, height: 10))
        let key = "test_image"
        
        cache.setImage(image, forKey: key)
        XCTAssertEqual(cache.getImage(forKey: key), image)
        
        cache.clear()
        XCTAssertNil(cache.getImage(forKey: key))
    }
}
