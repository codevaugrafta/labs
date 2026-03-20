// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Tiempo",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Tiempo", targets: ["Tiempo"])
    ],
    targets: [
        .executableTarget(
            name: "Tiempo",
            path: "Sources"
        ),
        .testTarget(
            name: "TiempoTests",
            dependencies: ["Tiempo"],
            path: "Tests"
        )
    ]
)
