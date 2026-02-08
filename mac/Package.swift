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
            name: "OpenMultitouchSupport",
            targets: ["OpenMultitouchSupport"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "OpenMultitouchSupportXCF",
            // For development: use local framework
            path: "OpenMultitouchSupportXCF.xcframework"
            // For release: use GitHub URL (replaced by release script)
            // url: "https://github.com/disarmyouwitha/GlassToKey/releases/download/v2.0.1/OpenMultitouchSupportXCF.xcframework.zip",
            // checksum: "5b69b4e180daffaff85fa76e4a211e0290a7ab8c4b49be31aa962bda1fe40fc0"
        ),
        .target(
            name: "OpenMultitouchSupport",
            dependencies: ["OpenMultitouchSupportXCF"],
            swiftSettings: swiftSettings
        )
    ]
) 
