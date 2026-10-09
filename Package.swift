// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LLMUsage",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LLMUsage", targets: ["LLMUsage"])],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "LLMUsage", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"])
    ]
)
