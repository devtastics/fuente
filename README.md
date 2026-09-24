# Fuente

A native, lightweight code editor for macOS, built from scratch in Swift and AppKit and designed to feel like it came from Apple.

> Early development. Nothing to run yet.

## Principles

- **Native first.** AppKit for the shell and the editor; SwiftUI only for leaf views. No web views, no custom rendering stacks.
- **Own text engine.** Built on CoreText, designed for code: large files, fast layout, precise control.
- **Language agnostic.** Syntax and semantics come from tree-sitter grammars and, later, LSP servers. PHP is the first language we test against, not a special case.
- **Small core.** Packages under `Packages/` are independent Swift packages with their own tests. The app is a thin shell on top.

## Requirements

| Target | Minimum |
|---|---|
| Fuente.app | macOS 26 (Tahoe), Apple Silicon |
| Packages | macOS 15 (Sequoia) |
| Toolchain | Xcode 26 / Swift 6.2 |

Packages target one version lower than the app on purpose: they must never depend on Tahoe-only APIs. CI enforces this by building and testing them on a macOS 15 runner.

## Building

The Xcode project is generated from `project.yml` with [xcodegen](https://github.com/yonaskolb/XcodeGen) and is not committed.

```sh
brew install xcodegen
xcodegen generate
open Fuente.xcodeproj
```

Packages build and test on their own, without Xcode:

```sh
cd Packages/FuenteText
swift build
swift test
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Every commit needs a `Signed-off-by` line (DCO).

## License

Apache License 2.0. See [LICENSE](LICENSE).

"Fuente" and the Fuente logo are trademarks of the project. The code is free to use and modify under the license; the name is not. Forks must ship under a different name.
