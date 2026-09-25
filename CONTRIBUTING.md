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

## Performance work

Fuente exists to be light. Measure before and after any change that touches the engine, and keep the
numbers in the pull request.

- **Debug HUD.** Debug builds have Debug > Toggle Performance HUD (Cmd+Opt+P): memory footprint, CPU,
  and the last draw, layout, edit and highlight timings. It shows the symptom, not the cause.
- **Performance tests.** `Packages/FuenteText` and `Packages/FuenteSyntax` have `PerformanceTests`
  suites with budgets. They run only in release, because debug builds measure the missing optimizer:

  ```sh
  swift test -c release -Xswiftc -enable-testing --filter PerformanceTests
  ```

- **Memory by category.** `footprint <pid>` separates heap from graphics memory (layer backing stores,
  IOSurfaces). `heap --sortBySize <pid>` lists the heap by class. Both work on debug builds without
  special permissions. Most surprises so far were graphics, not heap.
- **View in isolation.** `Tools/measure-memory.sh` shows the editor view in a bare window per
  configuration and prints its footprint, so the app's other pieces don't get in the way:

  ```sh
  Tools/measure-memory.sh
  Tools/measure-memory.sh "--huge --php" "--nstextview --huge"
  ```

- **Instruments.** The engine emits signposts under `com.devtastics.fuente` (`draw`, `layout`,
  `parse`, `query`); Time Profiler shows them as lanes. For a one-off backtrace of who allocates
  something, `lldb` with a breakpoint on the allocator (for example `CABackingStorePrepareUpdates_`)
  has been faster than a full trace.
