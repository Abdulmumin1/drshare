// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "drshare",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "DrShareMac",
            targets: ["DrShareMac"]
        ),
        .library(
            name: "DrShareShared",
            targets: ["DrShareShared"]
        ),
        .library(
            name: "DrShareWebAssets",
            targets: ["DrShareWebAssets"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "DrShareMac",
            dependencies: [
                "DrShareShared",
                "DrShareWebAssets",
            ],
            path: "mac-app/Sources/DrShareMac"
        ),
        .target(
            name: "DrShareShared",
            path: "shared/Sources/DrShareShared"
        ),
        .target(
            name: "DrShareWebAssets",
            path: "web-client/Sources/DrShareWebAssets",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
