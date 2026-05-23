// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeowOut",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "MeowOut",
            dependencies: [
                "KeyboardShortcuts"
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
            name: "MeowOutTests",
            dependencies: ["MeowOut"]
        )
    ]
)

