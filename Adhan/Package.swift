// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AdhanApp",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "AdhanApp", targets: ["AdhanApp"])
    ],
    dependencies: [
        // Pinned revision (was `main`) for reproducible builds — bump intentionally when upgrading adhan-swift.
        .package(url: "https://github.com/batoulapps/adhan-swift", revision: "127280c27c303f7898f59070580f4789a75df628")
    ],
    targets: [
        .executableTarget(
            name: "AdhanApp",
            dependencies: [
                .product(name: "Adhan", package: "adhan-swift")
            ],
            path: "Sources",
            exclude: ["Resources/Info.plist", "Resources/Adhan.entitlements", "Resources/Audio", "Resources/AppIcon.icns"]
        ),
        .testTarget(
            name: "AdhanAppTests",
            dependencies: ["AdhanApp"],
            path: "Tests"
        )
    ]
)
