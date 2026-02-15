// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VoiceSwap",
    platforms: [
        .iOS(.v17),  // Meta Wearables DAT requires iOS 17+
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VoiceSwap",
            targets: ["VoiceSwap"]
        ),
    ],
    dependencies: [
        // Meta Wearables Device Access Toolkit
        .package(url: "https://github.com/facebook/meta-wearables-dat-ios.git", exact: "0.4.0"),
        // secp256k1 for local Ethereum transaction signing
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", exact: "0.18.0"),
    ],
    targets: [
        .target(
            name: "VoiceSwap",
            dependencies: [
                .product(name: "MWDATCore", package: "meta-wearables-dat-ios"),
                .product(name: "MWDATCamera", package: "meta-wearables-dat-ios"),
                .product(name: "secp256k1", package: "secp256k1.swift"),
            ],
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
