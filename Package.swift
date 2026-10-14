// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Hodor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HodorCore"),
        .target(name: "HodorUI", dependencies: ["HodorCore"]),
        .executableTarget(name: "Hodor", dependencies: ["HodorCore", "HodorUI"]),
        .testTarget(name: "HodorCoreTests", dependencies: ["HodorCore"]),
        .testTarget(name: "HodorUITests", dependencies: ["HodorCore", "HodorUI"]),
    ]
)
