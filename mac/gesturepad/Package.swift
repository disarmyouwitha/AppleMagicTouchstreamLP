// swift-tools-version: 6.0

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "GesturePad",
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
        .target(name: "RewriteProbeKit", dependencies: ["ReplayFixtureKit"]),
        .executableTarget(name: "RewriteProbe", dependencies: ["RewriteProbeKit", "ReplayFixtureKit"]),
        .testTarget(name: "RewriteProbeTests", dependencies: ["RewriteProbeKit", "ReplayFixtureKit"]),
        // Compile the app's production sources directly, without launching its UI.
        .target(
            name: "GesturePadRuntime",
            dependencies: ["OpenMultitouchSupport", "ReplayFixtureKit"],
            path: "GesturePad/GesturePad",
            exclude: ["GesturePadApp.swift", "Assets.xcassets", "GesturePad.entitlements"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ProductionEngineTests",
            dependencies: ["GesturePadRuntime", "ReplayFixtureKit"],
            path: "Tests/ProductionEngineTests"
        ),
        .executableTarget(
            name: "ReplayFixtureCapture",
            dependencies: ["OpenMultitouchSupport", "ReplayFixtureKit"],
            path: "Tools/ReplayFixtureCapture"
        ),
        .executableTarget(
            name: "ReplayHarness",
            dependencies: ["ReplayFixtureKit", "GesturePadRuntime"],
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
            dependencies: ["ReplayFixtureKit", "OpenMultitouchSupport"],
            path: "Tests/ReplayFixtureKitTests"
        )
    ]
) 
