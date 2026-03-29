// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SyncWave",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "SyncWave",
            dependencies: ["Sparkle"],
            path: "Sources/SyncWave"
        ),
        .testTarget(
            name: "SyncWaveTests",
            dependencies: ["SyncWave"],
            path: "Tests/SyncWaveTests"
        ),
    ]
)
