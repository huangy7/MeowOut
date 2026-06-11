import SwiftUI
import AppKit

@available(macOS 13.0, *)
@MainActor
func generate() {
    let imageUrl = URL(fileURLWithPath: "/Users/huangy/.gemini/antigravity-ide/brain/c7fd6831-2d11-4878-9b44-b79f2c4c5520/meowout_icon_mo_gradient_light_1781078892403.png")
    guard let nsImage = NSImage(contentsOf: imageUrl) else { return }
    let image = Image(nsImage: nsImage)
    
    // The original image is 1024x1024.
    // The squircle inside it is probably around 650x650.
    // We want to fill an 824x824 mask. So we scale the image by 824/650 ≈ 1.26.
    // Let's use 1.3 to be safe so the original corners are clipped away.
    
    let view = ZStack {
        image
            .resizable()
            .scaledToFill()
            .frame(width: 1024 * 1.35, height: 1024 * 1.35)
    }
    .frame(width: 824, height: 824)
    .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
    .shadow(color: Color.black.opacity(0.3), radius: 25, x: 0, y: 15)
    .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 2)
    .frame(width: 1024, height: 1024)
    
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1.0
    renderer.isOpaque = false
    
    if let cgImage = renderer.cgImage {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        if let data = rep.representation(using: .png, properties: [:]) {
            try! data.write(to: URL(fileURLWithPath: "Sources/MeowOut/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png"))
            print("Extracted!")
        }
    }
}

if #available(macOS 13.0, *) {
    Task { @MainActor in
        generate()
        exit(0)
    }
    RunLoop.main.run()
}
