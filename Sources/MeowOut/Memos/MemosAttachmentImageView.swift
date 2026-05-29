import SwiftUI
import MemosKit

struct MemosAttachmentImageView: View {
    let url: URL
    var contentMode: ContentMode = .fill
    @State private var cgImage: CGImage?
    @State private var isLoading = false
    @State private var loadError = false

    var body: some View {
        ZStack {
            if let cgImage {
                Image(cgImage, scale: 1.0, orientation: .up, label: Text(""))
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading {
                VStack {
                    ProgressView()
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.03))
            } else if loadError {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.03))
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            isLoading = true
            loadError = false
            do {
                self.cgImage = try await MemosImageLoader.shared.image(from: url)
            } catch {
                print("Failed to load memo attachment image: \(error)")
                loadError = true
            }
            isLoading = false
        }
    }
}

