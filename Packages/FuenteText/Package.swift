// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FuenteText",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FuenteText", targets: ["FuenteText"]),
    ],
    targets: [
        .target(
            name: "FuenteText",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "FuenteTextTests",
            dependencies: ["FuenteText"]
        ),
    ]
)
