// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EzyRevenue",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "EzyRevenue",
            targets: ["EzyRevenue"]
        ),
    ],
    targets: [
        .target(
            name: "EzyRevenue",
            path: "Sources/EzyRevenue"
        ),
        .testTarget(
            name: "EzyRevenueTests",
            dependencies: ["EzyRevenue"],
            path: "Tests/EzyRevenueTests",
            resources: [
                .process("Fixtures"),
            ]
        ),
    ]
)
