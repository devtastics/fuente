// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FuenteSyntax",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FuenteSyntax", targets: ["FuenteSyntax"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/tree-sitter.git", "0.26.0"..<"0.27.0"),
        .package(path: "../Grammars/TreeSitterPHP"),
        .package(path: "../FuenteText"),
    ],
    targets: [
        .target(
            name: "FuenteSyntax",
            dependencies: [
                .product(name: "TreeSitter", package: "tree-sitter"),
                .product(name: "TreeSitterPHP", package: "TreeSitterPHP"),
                .product(name: "FuenteText", package: "FuenteText"),
            ],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "FuenteSyntaxTests",
            dependencies: ["FuenteSyntax"]
        ),
    ]
)
