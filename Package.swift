// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RunTime",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "UsageCore"),
        .target(name: "GameCore"),
        .target(name: "SearchCore"),
        .executableTarget(
            name: "RunTime",
            dependencies: ["UsageCore", "GameCore", "SearchCore"],
            resources: [.copy("Assets")]
        ),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
        .testTarget(name: "GameCoreTests", dependencies: ["GameCore"]),
        .testTarget(name: "SearchCoreTests", dependencies: ["SearchCore"]),
    ]
)
