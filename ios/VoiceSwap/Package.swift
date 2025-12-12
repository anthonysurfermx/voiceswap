// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VoiceSwap",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "VoiceSwap",
            targets: ["VoiceSwap"]
        ),
    ],
    dependencies: [
        // Add any external dependencies here
        // Example: .package(url: "https://github.com/example/package.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "VoiceSwap",
            dependencies: [],
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "VoiceSwapTests",
            dependencies: ["VoiceSwap"],
            path: "Tests"
        ),
    ]
)
