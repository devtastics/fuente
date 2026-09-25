import AppKit
import Testing
import FuenteText
@testable import FuenteSyntax

@Suite @MainActor struct SyntaxHighlighterTests {
    @Test func colorsArriveInTheTextView() async throws {
        let textView = TextView(storage: TextStorage("<?php echo \"x\";"))
        let highlighter = SyntaxHighlighter(textView: textView, language: Languages.php, theme: .system)
        // Wait for the background pass to land.
        for _ in 0..<50 where textView.layoutManager.styles(in: 0..<100).isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        let styles = textView.layoutManager.styles(in: 0..<100)
        #expect(styles.contains { $0.range == 0..<5 && $0.color == NSColor.systemOrange })   // <?php as tag
        #expect(styles.contains { $0.range == 11..<14 && $0.color == NSColor.systemRed })    // "x" as string
        _ = highlighter
    }
}
