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
        // Compile the app's production sources directly, without launching its UI.
        .target(
            name: "GlassToKeyRuntime",
            dependencies: ["OpenMultitouchSupport", "ReplayFixtureKit"],
            path: "GlassToKey/GlassToKey",
            exclude: ["GlassToKeyApp.swift", "Assets.xcassets", "GlassToKey.entitlements",
                      "GLASSTOKEY_DEFAULT_KEYMAP.json", "MY_KEYMAP.json"],
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ProductionEngineTests",
            dependencies: ["GlassToKeyRuntime", "ReplayFixtureKit"],
            path: "Tests/ProductionEngineTests"
        ),
        .executableTarget(
            name: "ReplayFixtureCapture",
            dependencies: ["OpenMultitouchSupport", "ReplayFixtureKit"],
            path: "Tools/ReplayFixtureCapture"
        ),
        .executableTarget(
            name: "ReplayHarness",
            dependencies: ["ReplayFixtureKit", "GlassToKeyRuntime"],
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
