// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenCat",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "UsageCore"),
        .target(name: "GameCore"),
        .executableTarget(
            name: "TokenCat",
            dependencies: ["UsageCore", "GameCore"],
            resources: [.copy("Assets")]
        ),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
        .testTarget(name: "GameCoreTests", dependencies: ["GameCore"]),
    ]
)
