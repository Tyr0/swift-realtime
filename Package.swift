// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-realtime",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .watchOS(.v26),
        .tvOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(
            name: "Realtime",
            targets: ["Realtime"],
        ),
    ],
    targets: [
        .target(
            name: "Realtime",
        ),
        .testTarget(
            name: "RealtimeTests",
            dependencies: [
                "Realtime",
            ],
        ),
    ],
)
