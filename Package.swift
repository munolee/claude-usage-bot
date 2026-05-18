// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClaudeUsageBot",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "claudeusagebot", targets: ["claudeusagebot"]),
        .executable(name: "spriterender", targets: ["spriterender"]),
        .library(name: "ClaudeUsageCore", targets: ["ClaudeUsageCore"])
    ],
    targets: [
        .target(name: "ClaudeUsageCore"),
        .executableTarget(
            name: "claudeusagebot",
            dependencies: ["ClaudeUsageCore"],
            path: "Sources/claudeusagebot"
        ),
        .executableTarget(
            name: "spriterender",
            dependencies: ["ClaudeUsageCore"],
            path: "Sources/spriterender"
        ),
        .testTarget(
            name: "ClaudeUsageCoreTests",
            dependencies: ["ClaudeUsageCore"]
        )
    ]
)
