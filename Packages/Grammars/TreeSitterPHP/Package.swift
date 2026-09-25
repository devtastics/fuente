// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TreeSitterPHP",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TreeSitterPHP", targets: ["TreeSitterPHP"]),
    ],
    targets: [
        .target(
            name: "TreeSitterPHPParser",
            path: "php/src",
            sources: ["parser.c", "scanner.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath(".")]
        ),
        .target(
            name: "TreeSitterPHP",
            dependencies: ["TreeSitterPHPParser"],
            resources: [.copy("queries")]
        ),
    ],
    cLanguageStandard: .c11
)
