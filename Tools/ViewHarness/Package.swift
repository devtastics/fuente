// swift-tools-version: 6.2
import PackageDescription

// Development tool: shows the editor view in a bare window so its memory and drawing can be measured
// in isolation. See Tools/measure-memory.sh.
let package = Package(
    name: "ViewHarness",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../Packages/FuenteText"),
        .package(path: "../../Packages/FuenteSyntax"),
    ],
    targets: [
        .executableTarget(
            name: "ViewHarness",
            dependencies: [
                .product(name: "FuenteText", package: "FuenteText"),
                .product(name: "FuenteSyntax", package: "FuenteSyntax"),
            ]
        ),
    ]
)
