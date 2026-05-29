import Foundation
import AppKit
import UniformTypeIdentifiers
import MemosKit

@MainActor
class ImageUploadManager: ObservableObject {
    static let shared = ImageUploadManager()
    
    @Published private(set) var activeUploadCount = 0
    
    var isUploading: Bool {
        activeUploadCount > 0
    }
    
    func uploadImage(data: Data, filename: String, mimeType: String) async throws -> Attachment {
        activeUploadCount += 1
        defer { activeUploadCount -= 1 }
        return try await MemosClient.shared.uploadAttachment(data: data, filename: filename, mimeType: mimeType)
    }
    
    func handlePasteboardImage() async -> (Data, String, String)? {
        let pboard = NSPasteboard.general
        if pboard.types?.contains(.png) == true, let data = pboard.data(forType: .png) {
            let filename = "pasted_image_\(UUID().uuidString.prefix(8)).png"
            return (data, filename, "image/png")
        }
        
        if pboard.types?.contains(.tiff) == true, let tiffData = pboard.data(forType: .tiff) {
            // Move TIFF-to-PNG conversion off the MainActor to prevent UI stuttering
            let pngData = await Task.detached(priority: .userInitiated) { () -> Data? in
                guard let imageRep = NSBitmapImageRep(data: tiffData) else { return nil }
                return imageRep.representation(using: .png, properties: [:])
            }.value
            
            if let pngData {
                let filename = "pasted_image_\(UUID().uuidString.prefix(8)).png"
                return (pngData, filename, "image/png")
            }
        }
        return nil
    }
}

