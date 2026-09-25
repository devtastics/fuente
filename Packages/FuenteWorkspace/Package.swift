// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FuenteWorkspace",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FuenteWorkspace", targets: ["FuenteWorkspace"]),
    ],
    targets: [
        .target(
            name: "FuenteWorkspace",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "FuenteWorkspaceTests",
            dependencies: ["FuenteWorkspace"]
        ),
    ]
)
