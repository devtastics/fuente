import AppKit
import Testing
@testable import FuenteText

@Suite @MainActor struct StylesTests {
    let typesetter = LineTypesetter(font: NSFont(name: "Menlo", size: 12)!)

    private func manager(_ text: String) -> TextLayoutManager {
        TextLayoutManager(storage: TextStorage(text), typesetter: typesetter)
    }

    @Test func stylesAreSlicedPerLineAndMadeLocal() {
        let manager = manager("abc\ndef\nghi")
        manager.setStyles([
            StyledRange(range: 1..<2, color: .red),      // "b"
            StyledRange(range: 2..<9, color: .blue),     // "c\ndef\ng": spans three lines
            StyledRange(range: 8..<9, color: .green),    // "g", nested in the blue one
        ])
        #expect(manager.styles(in: 0..<3) == [StyledRange(range: 1..<2, color: .red), StyledRange(range: 2..<3, color: .blue)])
        #expect(manager.styles(in: 4..<7) == [StyledRange(range: 0..<3, color: .blue)])
        #expect(manager.styles(in: 8..<11) == [StyledRange(range: 0..<1, color: .blue), StyledRange(range: 0..<1, color: .green)])
    }

    @Test func settingStylesKeepsHeightsButRedoesGlyphRuns() {
        let manager = manager("aaa\nbbb")
        _ = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 1000))
        let height = manager.contentHeight
        manager.setStyles([StyledRange(range: 0..<3, color: .red)])
        #expect(!manager.isLaidOut(0) && !manager.isLaidOut(1))
        #expect(manager.contentHeight == height)
    }

    @Test func editsShiftAndDropStyles() {
        let manager = manager("abc def ghi")
        manager.setStyles([
            StyledRange(range: 0..<3, color: .red),
            StyledRange(range: 4..<7, color: .green),
            StyledRange(range: 8..<11, color: .blue),
        ])
        manager.replace(5..<6, with: "XX")   // inside the green one: it goes; blue shifts by +1
        #expect(manager.styles(in: 0..<12) == [
            StyledRange(range: 0..<3, color: .red),
            StyledRange(range: 9..<12, color: .blue),
        ])
    }

    @Test func styledTextDrawsInColor() {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let textView = TextView(storage: TextStorage("XXXXXXXX"), typesetter: typesetter)
        scrollView.documentView = textView
        scrollView.layoutSubtreeIfNeeded()
        textView.backgroundColor = .white
        textView.textColor = .black
        textView.setStyles([StyledRange(range: 0..<8, color: .red)])

        let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds)!
        textView.cacheDisplay(in: textView.bounds, to: rep)
        var reddish = 0, blackish = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if c.redComponent > 0.6 && c.greenComponent < 0.4 && c.blueComponent < 0.4 { reddish += 1 }
                if c.brightnessComponent < 0.3 { blackish += 1 }
            }
        }
        #expect(reddish > 0)
        #expect(blackish == 0)
    }

    @Test func textDidChangeNotificationIsPosted() {
        let textView = TextView(storage: TextStorage(""), typesetter: typesetter)
        var received = 0
        let token = NotificationCenter.default.addObserver(forName: TextView.textDidChangeNotification, object: textView, queue: nil) { _ in
            received += 1
        }
        textView.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
        NotificationCenter.default.removeObserver(token)
        #expect(received == 1)
    }
}
