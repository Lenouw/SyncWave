// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SyncWave",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SyncWave",
            path: "Sources/SyncWave"
        ),
        .testTarget(
            name: "SyncWaveTests",
            dependencies: ["SyncWave"],
            path: "Tests/SyncWaveTests"
        ),
    ]
)
