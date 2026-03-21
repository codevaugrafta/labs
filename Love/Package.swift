// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Love",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Love", targets: ["Love"])
    ],
    targets: [
        .executableTarget(
            name: "Love",
            path: "Sources"
        ),
        .testTarget(
            name: "LoveTests",
            dependencies: ["Love"],
            path: "Tests"
        )
    ]
)
