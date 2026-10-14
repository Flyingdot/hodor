// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Hodor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HodorCore"),
        .executableTarget(name: "Hodor", dependencies: ["HodorCore"]),
        .testTarget(name: "HodorCoreTests", dependencies: ["HodorCore"]),
    ]
)
