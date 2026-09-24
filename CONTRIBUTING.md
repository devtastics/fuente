# Contributing to Fuente

## Developer Certificate of Origin

We use the [DCO](https://developercertificate.org) instead of a CLA. By adding a `Signed-off-by` line to your commit you certify that you wrote the code or have the right to submit it under the project license.

Sign off each commit with:

```sh
git commit -s
```

Pull requests with unsigned commits are not merged.

## Ground rules

- **Swift 6, strict concurrency.** Everything compiles in Swift 6 language mode with complete concurrency checking. No `@unchecked Sendable` without a comment explaining why.
- **Packages target macOS 15.** Tahoe-only APIs live in the app shell. If you need one inside a package, guard it with `#available(macOS 26, *)` and provide a fallback.
- **AppKit in packages, SwiftUI in the app.** The text engine and every package view are `NSView` subclasses.
- **Tests are part of the change.** New behavior in a package comes with Swift Testing tests in the same PR.
- **Small, surgical PRs.** One change per PR. Don't reformat or refactor code you're not touching.

## Trademark

"Fuente" is the name of this project. You may build and distribute the code under the Apache 2.0 license, but a modified distribution must not use the Fuente name or logo.
