// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LuxAnalytics",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "LuxAnalytics", targets: ["LuxAnalytics"])
    ],
    targets: [
        .target(
            name: "LuxAnalytics",
            dependencies: [],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [
                // We want Swift 6 with all its safety features!
            ]
        ),
        .testTarget(name: "LuxAnalyticsTests", dependencies: ["LuxAnalytics"])
    ]
)
