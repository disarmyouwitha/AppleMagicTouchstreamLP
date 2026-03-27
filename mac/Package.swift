// swift-tools-version: 6.0

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "OpenMultitouchSupport",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "OpenMultitouchSupportBridge",
            targets: ["OpenMultitouchSupportXCF"]
        ),
        .library(
            name: "OpenMultitouchSupport",
            targets: ["OpenMultitouchSupport"]
        ),
        .library(
            name: "ReplayFixtureKit",
            targets: ["ReplayFixtureKit"]
        )
    ],
    targets: [
        .target(
            name: "OpenMultitouchSupportXCF",
            path: "Framework/OpenMultitouchSupportXCF",
            publicHeadersPath: ".",
            cSettings: [
                .unsafeFlags(["-fobjc-arc"])
            ],
            linkerSettings: [
                .unsafeFlags(["-F/System/Library/PrivateFrameworks"]),
                .linkedFramework("Cocoa"),
                .linkedFramework("Foundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("MultitouchSupport")
            ]
        ),
        .target(
            name: "OpenMultitouchSupport",
            dependencies: ["OpenMultitouchSupportXCF"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "ReplayFixtureKit",
            dependencies: []
        ),
        .executableTarget(
            name: "ReplayFixtureCapture",
            dependencies: ["OpenMultitouchSupport", "ReplayFixtureKit"],
            path: "Tools/ReplayFixtureCapture"
        ),
        .executableTarget(
            name: "ReplayHarness",
            dependencies: ["ReplayFixtureKit"],
            path: "Tools/ReplayHarness"
        ),
        .executableTarget(
            name: "RawCaptureAnalyze",
            dependencies: ["ReplayFixtureKit"],
            path: "Tools/RawCaptureAnalyze"
        ),
        .executableTarget(
            name: "ATPCaptureTranscode",
            dependencies: ["ReplayFixtureKit"],
            path: "Tools/ATPCaptureTranscode"
        ),
        .testTarget(
            name: "ReplayFixtureKitTests",
            dependencies: ["ReplayFixtureKit"],
            path: "Tests/ReplayFixtureKitTests"
        )
    ]
) 
