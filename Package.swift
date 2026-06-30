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
    dependencies: [
        .package(url: "https://github.com/Tyr0/swift-streams.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "Realtime",
        ),
        .target(
            name: "Realtime_Streams",
            dependencies: [
                "Realtime",
                .product(name: "Streams", package: "swift-streams"),
            ],
        ),
        .testTarget(
            name: "RealtimeTests",
            dependencies: [
                "Realtime",
                "Realtime_Streams",
            ],
        ),
    ],
)
