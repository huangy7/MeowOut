// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeowOut",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0")
    ],
    targets: [
        .target(
            name: "MemosKit",
            dependencies: []
        ),
        .executableTarget(
            name: "MeowOut",
            dependencies: [
                "KeyboardShortcuts",
                "MemosKit",
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            exclude: ["Info.plist"],
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "MemosKitTests",
            dependencies: ["MemosKit"]
        ),
        .testTarget(
            name: "MeowOutTests",
            dependencies: ["MeowOut"]
        )
    ]
)

