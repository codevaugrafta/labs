// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VoiceTutor",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "VoiceTutor", targets: ["VoiceTutor"])
    ],
    dependencies: [
        .package(url: "https://github.com/elevenlabs/elevenlabs-swift-sdk.git", from: "3.1.0")
    ],
    targets: [
        .executableTarget(
            name: "VoiceTutor",
            dependencies: [
                .product(name: "ElevenLabs", package: "elevenlabs-swift-sdk")
            ],
            path: "Sources/VoiceTutor"
        ),
        .testTarget(
            name: "VoiceTutorTests",
            dependencies: ["VoiceTutor"],
            path: "Tests"
        )
    ]
)
