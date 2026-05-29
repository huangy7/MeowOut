import SwiftUI
import MemosKit
import AppKit

struct MemoImagePreviewOverlay: View {
    let url: URL
    @Environment(AppState.self) private var appState
    
    @State private var scale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero

    var body: some View {
        ZStack {
            // Dark Background covering the whole screen
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    close()
                }

            // Image Container
            GeometryReader { geometry in
                let size = geometry.size
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        MemosAttachmentImageView(url: url, contentMode: .fit)
                            .scaleEffect(scale)
                            .offset(dragOffset + accumulatedOffset)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        dragOffset = value.translation
                                    }
                                    .onEnded { value in
                                        accumulatedOffset = accumulatedOffset + value.translation
                                        dragOffset = .zero
                                    }
                            )
                            .frame(maxWidth: max(100, size.width - 80), maxHeight: max(100, size.height - 120))
                        Spacer()
                    }
                    Spacer()
                }
            }

            // Toolbar Layer
            VStack {
                HStack {
                    Spacer()
                    // Close button
                    Button(action: close) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(16)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                
                // Bottom control panel
                HStack(spacing: 20) {
                    // Zoom Out
                    Button(action: zoomOut) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help("缩小")
                    
                    // Zoom Scale Text
                    Text("\(Int(scale * 100))%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48)
                    
                    // Zoom In
                    Button(action: zoomIn) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help("放大")
                    
                    // Reset Scale
                    Button(action: resetScale) {
                        Image(systemName: "arrow.counterclockwise.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help("重置")
                    
                    Divider()
                        .frame(width: 1, height: 16)
                        .background(Color.white.opacity(0.3))
                    
                    // Copy Image
                    Button(action: copyImage) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help("复制图片")
                    
                    // Save to Disk
                    Button(action: saveToDisk) {
                        Image(systemName: "arrow.down.to.line.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help("保存到磁盘")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .padding(.bottom, 24)
            }
        }
        .onExitCommand {
            close()
        }
    }
    
    private func close() {
        appState.activeImageURL = nil
    }
    
    private func zoomIn() {
        withAnimation(.interactiveSpring) {
            scale = min(scale + 0.25, 4.0)
        }
    }
    
    private func zoomOut() {
        withAnimation(.interactiveSpring) {
            scale = max(scale - 0.25, 0.25)
            if scale == 1.0 {
                dragOffset = .zero
                accumulatedOffset = .zero
            }
        }
    }
    
    private func resetScale() {
        withAnimation(.interactiveSpring) {
            scale = 1.0
            dragOffset = .zero
            accumulatedOffset = .zero
        }
    }
    
    private func copyImage() {
        Task {
            if let cgImage = try? await MemosImageLoader.shared.image(from: url) {
                let nsImage = NSImage(cgImage: cgImage, size: .zero)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([nsImage])
            }
        }
    }
    
    private func saveToDisk() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]
        savePanel.nameFieldStringValue = url.lastPathComponent
        savePanel.begin { response in
            guard response == .OK, let destinationURL = savePanel.url else { return }
            Task {
                do {
                    let cgImage = try await MemosImageLoader.shared.image(from: url)
                    let nsImage = NSImage(cgImage: cgImage, size: .zero)
                    if let tiffData = nsImage.tiffRepresentation,
                       let imageRep = NSBitmapImageRep(data: tiffData),
                       let pngData = imageRep.representation(using: .png, properties: [:]) {
                        try pngData.write(to: destinationURL)
                    }
                } catch {
                    print("Failed to save image to disk: \(error)")
                }
            }
        }
    }
}

// CGSize mathematical operator helpers
private func +(lhs: CGSize, rhs: CGSize) -> CGSize {
    CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
}
