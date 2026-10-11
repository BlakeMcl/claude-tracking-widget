// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsageWidget",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClaudeUsageCore", targets: ["ClaudeUsageCore"]),
        .executable(name: "claude-usage-collector", targets: ["claude-usage-collector"]),
    ],
    targets: [
        .target(name: "ClaudeUsageCore"),
        .executableTarget(name: "claude-usage-collector", dependencies: ["ClaudeUsageCore"]),
        .testTarget(name: "ClaudeUsageCoreTests", dependencies: ["ClaudeUsageCore"], resources: [.copy("Fixtures")]),
    ]
)
