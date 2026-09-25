import AppKit
import Testing
@testable import FuenteText

/// Budgets are 5-10x what an M-series Mac does in release, so CI runners pass and real regressions fail.
/// Debug builds are 50-100x slower on tight loops and would only measure the optimizer's absence.
@Suite(.serialized, .disabled(if: isDebugBuild, "performance budgets only mean something in release"))
@MainActor struct PerformanceTests {
    static let bigText: String = (0..<100_000).map { "    $line\($0) = compute(\($0), \"text\"); // comment \($0)" }.joined(separator: "\n")

    private func measure(_ label: String, _ body: () -> Void) -> Duration {
        let clock = ContinuousClock()
        let elapsed = clock.measure(body)
        print("PERF \(label): \(elapsed)")
        return elapsed
    }

    @Test func openingAHundredThousandLines() {
        var storage: TextStorage!
        let build = measure("TextStorage init 100k lines") { storage = TextStorage(Self.bigText) }
        #expect(build < .milliseconds(250))
        #expect(storage.lineCount == 100_000)

        var manager: TextLayoutManager!
        let layout = measure("TextLayoutManager init 100k lines") {
            manager = TextLayoutManager(storage: storage, typesetter: LineTypesetter(font: NSFont(name: "Menlo", size: 12)!))
        }
        #expect(layout < .milliseconds(80))

        let viewport = measure("layoutLines viewport of 60 lines") {
            _ = manager.layoutLines(in: CGRect(x: 0, y: 5_000 * 15, width: 800, height: 60 * 15))
        }
        #expect(viewport < .milliseconds(10))
    }

    @Test func typingAThousandCharactersInABigDocument() {
        let manager = TextLayoutManager(storage: TextStorage(Self.bigText), typesetter: LineTypesetter(font: NSFont(name: "Menlo", size: 12)!))
        let middle = manager.storage.lineStarts[50_000]
        let typing = measure("1000 inserts in the middle of 100k lines") {
            for index in 0..<1000 {
                manager.replace((middle + index)..<(middle + index), with: "x")
            }
        }
        #expect(typing < .milliseconds(200))

        let newlines = measure("100 newline inserts (line count changes)") {
            for index in 0..<100 {
                manager.replace((middle + index)..<(middle + index), with: "\n")
            }
        }
        #expect(newlines < .milliseconds(1500))
    }

    @Test func editingThroughTheView() {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let textView = TextView(storage: TextStorage(Self.bigText), typesetter: LineTypesetter(font: NSFont(name: "Menlo", size: 12)!))
        scrollView.documentView = textView
        scrollView.layoutSubtreeIfNeeded()
        textView.selection = TextSelection(caret: textView.layoutManager.storage.lineStarts[50_000])
        let typing = measure("200 keystrokes through TextView") {
            for _ in 0..<200 {
                textView.insertText("y", replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }
        #expect(typing < .milliseconds(150))
    }
}

let isDebugBuild: Bool = {
    #if DEBUG
    true
    #else
    false
    #endif
}()
