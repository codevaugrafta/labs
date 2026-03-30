// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Leo",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Leo", targets: ["Leo"])
    ],
    dependencies: [
        .package(url: "https://github.com/httpswift/swifter.git", .upToNextMajor(from: "1.5.0")),
        .package(url: "https://github.com/soniqo/speech-swift", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "Leo",
            dependencies: [
                .product(name: "Swifter", package: "swifter"),
                .product(name: "Qwen3TTS", package: "speech-swift"),
                .product(name: "Qwen3ASR", package: "speech-swift"),
            ],
            path: "Sources",
            exclude: ["Resources/Info.plist", "Resources/Leo.entitlements"],
            resources: [
                .copy("Resources/Dictionary"),
                .copy("Resources/web"),
            ]
        ),
        .testTarget(
            name: "LeoTests",
            dependencies: ["Leo"],
            path: "Tests"
        )
    ]
)
