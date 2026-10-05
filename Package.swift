// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenCat",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(
            name: "TokenCat",
            dependencies: ["UsageCore"],
            resources: [.copy("Assets")]
        ),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ]
)
