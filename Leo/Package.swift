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
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "Leo",
            dependencies: ["SwiftSoup"],
            path: "Sources",
            exclude: ["Resources/Info.plist", "Resources/Leo.entitlements"],
            resources: [.copy("Resources/Dictionary")]
        ),
        .testTarget(
            name: "LeoTests",
            dependencies: ["Leo"],
            path: "Tests"
        )
    ]
)
