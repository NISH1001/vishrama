// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vishrama",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "VishramaCore"),
        .executableTarget(
            name: "Vishrama",
            dependencies: ["VishramaCore"]
        ),
        .testTarget(
            name: "VishramaCoreTests",
            dependencies: ["VishramaCore"]
        ),
    ]
)
