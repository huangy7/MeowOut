import SwiftUI
import AppKit

public struct AsyncClipboardImageView: View {
    let item: ClipboardItem
    let contentMode: ContentMode
    @State private var image: NSImage?
    
    public init(item: ClipboardItem, contentMode: ContentMode = .fit) {
        self.item = item
        self.contentMode = contentMode
    }
    
    public var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    Color.primary.opacity(0.06)
                    Image(systemName: "photo")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: item.id) {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        let key = item.id.uuidString
        if let cached = ClipboardImageCache.shared.getImage(forKey: key) {
            self.image = cached
            return
        }
        
        let loadedImage = await Task.detached(priority: .userInitiated) {
            return item.previewImage
        }.value
        
        if let loadedImage = loadedImage {
            ClipboardImageCache.shared.setImage(loadedImage, forKey: key)
            await MainActor.run {
                self.image = loadedImage
            }
        }
    }
}
