import AppKit
import Testing
@testable import FuenteText

@Suite @MainActor struct GutterRegressionTests {
    /// Rulers receive a dirty rect spanning the whole scroll view. The gutter must not paint over the text.
    @Test func gutterDoesNotCoverTextInAWindow() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        let textView = TextView(storage: TextStorage("# Fuente\n\nA native editor"), typesetter: LineTypesetter(font: NSFont(name: "Menlo", size: 12)!))
        textView.backgroundColor = .white
        textView.textColor = .black
        scrollView.documentView = textView
        let gutter = textView.installGutter()!
        gutter.backgroundColor = .white
        window.contentView = scrollView
        window.layoutIfNeeded()
        scrollView.tile()
        scrollView.layoutSubtreeIfNeeded()

        let rep = scrollView.bitmapImageRepForCachingDisplay(in: scrollView.bounds)!
        scrollView.cacheDisplay(in: scrollView.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / scrollView.bounds.width
        var dark = 0
        for x in Int(gutter.frame.maxX * scale)..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.brightnessComponent ?? 1) < 0.5 { dark += 1 }
        }
        #expect(dark > 0)
    }
}
