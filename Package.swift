// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Tunneler",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TunnelerCore"),
        .executableTarget(name: "Tunneler", dependencies: ["TunnelerCore"]),
        .testTarget(name: "TunnelerCoreTests", dependencies: ["TunnelerCore"]),
    ]
)
