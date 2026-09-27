// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChaosKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "chaos", targets: ["chaos"]),
        .executable(name: "chaos-stress", targets: ["chaos-stress"]),
        .library(name: "ChaosKit", targets: ["ChaosKit"]),
    ],
    dependencies: [
        // Zero external dependencies: local-first, private by design.
    ],
    targets: [
        .target(
            name: "ChaosKit",
            path: "ChaosKit/Sources/ChaosKit"
        ),
        .executableTarget(
            name: "chaos",
            dependencies: ["ChaosKit"],
            path: "ChaosKit/Sources/chaos"
        ),
        .executableTarget(
            name: "chaos-stress",
            path: "ChaosKit/Sources/chaos-stress"
        ),
        .testTarget(
            name: "ChaosKitTests",
            dependencies: ["ChaosKit"],
            path: "ChaosKit/Tests/ChaosKitTests"
        ),
    ]
)
