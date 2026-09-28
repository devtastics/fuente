import AppKit
import Testing
@testable import FuenteText

@Suite @MainActor struct ErgonomicsTests {
    private let notFound = NSRange(location: NSNotFound, length: 0)

    private func view(_ text: String, caret: Int? = nil, selection: TextSelection? = nil) -> TextView {
        let textView = TextView(storage: TextStorage(text), typesetter: LineTypesetter(font: NSFont(name: "Menlo", size: 12)!))
        textView.lineCommentPrefix = "//"
        if let selection { textView.selection = selection } else if let caret { textView.selection = TextSelection(caret: caret) }
        return textView
    }

    private func type(_ text: String, into textView: TextView) {
        for character in text { textView.insertText(String(character), replacementRange: notFound) }
    }

    // MARK: Words

    @Test func wordRangeCoversIdentifiersAndPunctuation() {
        let textView = view("foo_bar($baz, 12);")
        #expect(textView.wordRange(at: 2) == 0..<7)      // foo_bar
        #expect(textView.wordRange(at: 7) == 7..<8)      // (
        #expect(textView.wordRange(at: 10) == 9..<12)    // baz (the $ is punctuation)
        #expect(textView.wordRange(at: 14) == 14..<16)   // 12
        #expect(textView.wordRange(at: 18) == 17..<18)   // ; at end of line
    }

    // MARK: Indent / outdent

    @Test func shiftRightAndLeftOnSelectedLines() {
        let textView = view("a\nb\nc\n", selection: TextSelection(anchor: 0, head: 3))   // "a\nb"
        textView.shiftRight(nil)
        #expect(textView.layoutManager.storage.string == "    a\n    b\nc\n")
        #expect(textView.selection == TextSelection(anchor: 4, head: 11))
        textView.shiftLeft(nil)
        #expect(textView.layoutManager.storage.string == "a\nb\nc\n")
        #expect(textView.selection == TextSelection(anchor: 0, head: 3))
        textView.undo(nil)
        #expect(textView.layoutManager.storage.string == "    a\n    b\nc\n")   // one undo step per shift
    }

    @Test func tabWithSelectionIndentsAndBacktabOutdentsPartialIndent() {
        let textView = view("  x\ny", selection: TextSelection(anchor: 0, head: 5))
        textView.insertTab(nil)
        #expect(textView.layoutManager.storage.string == "      x\n    y")
        textView.insertBacktab(nil)
        textView.insertBacktab(nil)
        #expect(textView.layoutManager.storage.string == "x\ny")   // removes at most one unit per line, never past content
    }

    // MARK: Comments

    @Test func toggleCommentAddsAtMinimumIndentAndRemoves() {
        let textView = view("    a\n\n  b\n", selection: TextSelection(anchor: 0, head: 10))
        textView.toggleComment(nil)
        #expect(textView.layoutManager.storage.string == "  //   a\n\n  // b\n")   // blank line untouched
        textView.toggleComment(nil)
        #expect(textView.layoutManager.storage.string == "    a\n\n  b\n")
    }

    @Test func toggleCommentOnACaretLine() {
        let textView = view("echo 1;", caret: 3)
        textView.toggleComment(nil)
        #expect(textView.layoutManager.storage.string == "// echo 1;")
        #expect(textView.selection == TextSelection(caret: 6))
        textView.toggleComment(nil)
        #expect(textView.layoutManager.storage.string == "echo 1;")
        #expect(textView.selection == TextSelection(caret: 3))
    }

    @Test func toggleCommentWithoutPrefixDoesNothing() {
        let textView = view("x", caret: 0)
        textView.lineCommentPrefix = nil
        textView.toggleComment(nil)
        #expect(textView.layoutManager.storage.string == "x")
    }

    // MARK: Line moves

    @Test func duplicateAndMoveLines() {
        let textView = view("one\ntwo\nthree", caret: 5)   // in "two"
        textView.duplicateLine(nil)
        #expect(textView.layoutManager.storage.string == "one\ntwo\ntwo\nthree")
        #expect(textView.selection == TextSelection(caret: 9))
        textView.moveLineUp(nil)
        textView.moveLineUp(nil)
        #expect(textView.layoutManager.storage.string == "two\none\ntwo\nthree")
        #expect(textView.selection == TextSelection(caret: 1))
        textView.moveLineUp(nil)   // already first: no-op
        #expect(textView.layoutManager.storage.string == "two\none\ntwo\nthree")
        textView.selection = TextSelection(caret: 4)
        textView.moveLineDown(nil)
        textView.moveLineDown(nil)
        #expect(textView.layoutManager.storage.string == "two\ntwo\nthree\none")
        textView.moveLineDown(nil)
        #expect(textView.layoutManager.storage.string == "two\ntwo\nthree\none")
    }

    @Test func duplicateLastLineWithoutNewline() {
        let textView = view("a\nb", caret: 3)
        textView.duplicateLine(nil)
        #expect(textView.layoutManager.storage.string == "a\nb\nb")
        #expect(textView.selection == TextSelection(caret: 5))
    }

    // MARK: Go to line

    @Test func goToLineClampsAndPlacesCaret() {
        let textView = view("a\nbb\nccc")
        textView.goToLine(2)
        #expect(textView.selection == TextSelection(caret: 2))
        textView.goToLine(99)
        #expect(textView.selection == TextSelection(caret: 5))
        textView.goToLine(-3)
        #expect(textView.selection == TextSelection(caret: 0))
    }

    // MARK: Brackets

    @Test func matchingBracketsAcrossNesting() {
        let textView = view("f(a[1], (b))")
        #expect(textView.matchingBracketRanges(at: 2)?.1 == 11..<12)   // after "(" at 1
        #expect(textView.matchingBracketRanges(at: 12)?.1 == 1..<2)    // after final ")"
        #expect(textView.matchingBracketRanges(at: 4)?.1 == 5..<6)     // after "["
        #expect(textView.matchingBracketRanges(at: 6)?.1 == 3..<4)     // after "]": matches the "["
        #expect(textView.matchingBracketRanges(at: 0) == nil)
    }

    @Test func autoClosePairsStepOverAndDelete() {
        let textView = view("", caret: 0)
        type("(", into: textView)
        #expect(textView.layoutManager.storage.string == "()")
        #expect(textView.selection == TextSelection(caret: 1))
        type("x", into: textView)
        type(")", into: textView)                                   // steps over the closer
        #expect(textView.layoutManager.storage.string == "(x)")
        #expect(textView.selection == TextSelection(caret: 3))
        type("\"", into: textView)
        #expect(textView.layoutManager.storage.string == "(x)\"\"")
        textView.deleteBackward(nil)                                 // empty pair goes at once
        #expect(textView.layoutManager.storage.string == "(x)")
    }

    @Test func autoCloseDoesNotFireBeforeText() {
        let textView = view("abc", caret: 0)
        type("(", into: textView)
        #expect(textView.layoutManager.storage.string == "(abc")   // next char is not a boundary
        let quoted = view("it", caret: 2)
        type("'", into: quoted)
        #expect(quoted.layoutManager.storage.string == "it'")      // apostrophe after a word
    }

    @Test func openerWrapsSelection() {
        let textView = view("hello", selection: TextSelection(anchor: 0, head: 5))
        type("[", into: textView)
        #expect(textView.layoutManager.storage.string == "[hello]")
        #expect(textView.selection == TextSelection(anchor: 1, head: 6))
    }

    @Test func returnBetweenBracesOpensABlock() {
        let textView = view("  if (x) {}", caret: 10)
        textView.insertNewline(nil)
        #expect(textView.layoutManager.storage.string == "  if (x) {\n      \n  }")
        #expect(textView.selection == TextSelection(caret: 17))
        textView.undo(nil)
        #expect(textView.layoutManager.storage.string == "  if (x) {}")
    }

    @Test func doubleAndTripleClickSelect() {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 100))
        let textView = view("hello world\nsecond")
        scrollView.documentView = textView
        scrollView.layoutSubtreeIfNeeded()
        let target = textView.layoutManager.caretRect(at: 7).offsetBy(dx: textView.textInset, dy: 0)
        // mouseDown converts from window (base) coordinates; produce the event there.
        let point = textView.convert(CGPoint(x: target.minX + 0.5, y: target.midY), to: nil)
        func click(_ count: Int) -> NSEvent {
            NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
        }
        textView.mouseDown(with: click(2))
        #expect(textView.selection == TextSelection(anchor: 6, head: 11))
        textView.mouseDown(with: click(3))
        #expect(textView.selection == TextSelection(anchor: 0, head: 12))
    }
}
