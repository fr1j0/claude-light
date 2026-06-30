// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeLight",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ClaudeLightCore"),
        .executableTarget(
            name: "claude-light-hook",
            dependencies: ["ClaudeLightCore"]
        ),
        .executableTarget(
            name: "ClaudeLightApp",
            dependencies: ["ClaudeLightCore"]
        ),
        .testTarget(
            name: "ClaudeLightCoreTests",
            dependencies: ["ClaudeLightCore"]
        ),
    ]
)
