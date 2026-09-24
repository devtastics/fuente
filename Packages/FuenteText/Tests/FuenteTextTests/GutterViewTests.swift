import AppKit
import Testing
@testable import FuenteText

@Suite @MainActor struct GutterViewTests {
    private func make(_ text: String) -> (NSScrollView, TextView, GutterView) {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let textView = TextView(storage: TextStorage(text), typesetter: LineTypesetter(font: NSFont(name: "Menlo", size: 12)!))
        scrollView.documentView = textView
        let gutter = textView.installGutter()!
        scrollView.layoutSubtreeIfNeeded()
        return (scrollView, textView, gutter)
    }

    @Test func thicknessGrowsWithDigits() {
        let (_, textView, gutter) = make((1...99).map(String.init).joined(separator: "\n"))
        let twoDigits = gutter.ruleThickness
        #expect(twoDigits == gutter.requiredThickness)

        textView.selection = TextSelection(caret: textView.layoutManager.storage.utf16Count)
        textView.insertNewline(nil)
        #expect(textView.layoutManager.lineCount == 100)
        #expect(gutter.ruleThickness > twoDigits)
    }

    @Test func gutterIsInstalledAsVerticalRuler() {
        let (scrollView, textView, gutter) = make("a\nb")
        #expect(scrollView.verticalRulerView === gutter)
        #expect(scrollView.rulersVisible)
        #expect(textView.gutter === gutter)
    }

    @Test func drawsNumbers() {
        let (_, _, gutter) = make("uno\ndos\ntres")
        gutter.backgroundColor = .white
        gutter.textColor = .black
        gutter.currentLineColor = .black
        let rep = gutter.bitmapImageRepForCachingDisplay(in: gutter.bounds)!
        gutter.cacheDisplay(in: gutter.bounds, to: rep)
        var dark = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.brightnessComponent ?? 1) < 0.5 {
                dark += 1
            }
        }
        #expect(dark > 0)
    }
}
