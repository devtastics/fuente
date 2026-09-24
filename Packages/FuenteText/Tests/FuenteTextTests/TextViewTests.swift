import AppKit
import Testing
@testable import FuenteText

@Suite @MainActor struct TextViewTests {
    /// A text view inside a scroll view of the given size, laid out once.
    private func makeScrollView(_ text: String, size: CGSize = CGSize(width: 300, height: 200)) -> (NSScrollView, TextView) {
        let scrollView = NSScrollView(frame: CGRect(origin: .zero, size: size))
        let textView = TextView(storage: TextStorage(text), typesetter: LineTypesetter(font: NSFont(name: "Menlo", size: 12)!))
        scrollView.documentView = textView
        scrollView.layoutSubtreeIfNeeded()
        return (scrollView, textView)
    }

    private func render(_ view: NSView) -> NSBitmapImageRep {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private func hasNonBackgroundPixels(_ rep: NSBitmapImageRep, background: NSColor) -> Bool {
        let bg = background.usingColorSpace(rep.colorSpace ?? .deviceRGB)!
        for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                if abs(color.redComponent - bg.redComponent) > 0.1
                    || abs(color.greenComponent - bg.greenComponent) > 0.1
                    || abs(color.blueComponent - bg.blueComponent) > 0.1 {
                    return true
                }
            }
        }
        return false
    }

    @Test func fillsScrollViewWhenDocumentIsShort() {
        let (scrollView, textView) = makeScrollView("hola")
        #expect(textView.frame.size == scrollView.contentView.bounds.size)
    }

    @Test func growsToDocumentHeightWhenLong() {
        let text = (0..<200).map { "line \($0)" }.joined(separator: "\n")
        let (scrollView, textView) = makeScrollView(text)
        #expect(textView.frame.height == textView.layoutManager.contentHeight)
        #expect(textView.frame.height > scrollView.contentView.bounds.height)
    }

    @Test func wrapWidthFollowsScrollViewWidth() {
        let (scrollView, textView) = makeScrollView("x", size: CGSize(width: 320, height: 100))
        #expect(textView.layoutManager.wrapWidth == 320 - textView.textInset * 2)

        textView.wrapsLines = false
        scrollView.layoutSubtreeIfNeeded()
        #expect(textView.layoutManager.wrapWidth == nil)
    }

    @Test func drawsGlyphs() {
        let (_, textView) = makeScrollView("<?php echo 'hola';")
        textView.backgroundColor = .white
        textView.textColor = .black
        let rep = render(textView)
        #expect(hasNonBackgroundPixels(rep, background: .white))
    }

    @Test func emptyDocumentDrawsOnlyBackground() {
        let (_, textView) = makeScrollView("")
        textView.backgroundColor = .white
        let rep = render(textView)
        #expect(!hasNonBackgroundPixels(rep, background: .white))
    }
}
