// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceAnywhere",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "VoiceAnywhere",
            dependencies: [
                "KeyboardShortcuts",
            ],
            path: "Sources/VoiceAnywhere",
            resources: [
                .process("../../Resources"),
            ]
        ),
    ]
)
