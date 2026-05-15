// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Reservoir",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Reservoir", targets: ["Reservoir"]),
        .executable(name: "UsageMonitorChecks", targets: ["UsageMonitorChecks"])
    ],
    targets: [
        .target(
            name: "UsageMonitorCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "Reservoir",
            dependencies: ["UsageMonitorCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "UsageMonitorChecks",
            dependencies: ["UsageMonitorCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
