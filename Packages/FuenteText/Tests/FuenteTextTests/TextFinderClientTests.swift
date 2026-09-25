import AppKit
import Testing
@testable import FuenteText

@Suite @MainActor struct TextFinderClientTests {
    private func view(_ text: String) -> (NSScrollView, TextView) {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let textView = TextView(storage: TextStorage(text), typesetter: LineTypesetter(font: NSFont(name: "Menlo", size: 12)!))
        scrollView.documentView = textView
        scrollView.layoutSubtreeIfNeeded()
        return (scrollView, textView)
    }

    @Test func finderIsInstalledInTheScrollView() {
        let (scrollView, textView) = view("abc")
        #expect(textView.textFinder.client === textView)
        #expect(textView.textFinder.findBarContainer === scrollView)
        #expect(scrollView.findBarPosition == .aboveContent)
    }

    @Test func exposesStringAndSelection() {
        let (_, textView) = view("hello world")
        #expect(textView.string == "hello world")
        textView.selectedRanges = [NSValue(range: NSRange(location: 6, length: 5))]
        #expect(textView.selection == TextSelection(anchor: 6, head: 11))
        #expect(textView.firstSelectedRange == NSRange(location: 6, length: 5))
    }

    @Test func rectsFollowLayout() {
        let (_, textView) = view("abc\ndef")
        let rects = textView.rects(forCharacterRange: NSRange(location: 1, length: 5))!.map(\.rectValue)
        #expect(rects.count == 2)
        #expect(rects[0].minX == textView.layoutManager.caretRect(at: 1).minX + textView.textInset)
        #expect(rects[1].minY > rects[0].minY)
    }

    @Test func visibleRangeCoversAShortDocument() {
        let (_, textView) = view("one\ntwo\nthree")
        #expect(textView.visibleCharacterRanges.first?.rangeValue == NSRange(location: 0, length: 13))
    }

    @Test func replaceGoesThroughUndo() {
        let (_, textView) = view("foo bar foo")
        textView.replaceCharacters(in: NSRange(location: 8, length: 3), with: "baz")
        #expect(textView.string == "foo bar baz")
        textView.undo(nil)
        #expect(textView.string == "foo bar foo")
    }
}
