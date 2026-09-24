import AppKit
import Testing
@testable import FuenteText

@Suite @MainActor struct TextViewNavigationTests {
    private func view(_ text: String, width: CGFloat = 300) -> TextView {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: width, height: 200))
        let textView = TextView(storage: TextStorage(text), typesetter: LineTypesetter(font: NSFont(name: "Menlo", size: 12)!))
        scrollView.documentView = textView
        scrollView.layoutSubtreeIfNeeded()
        return textView
    }

    @Test func horizontalMovesStepByGrapheme() {
        let textView = view("a😀b")
        textView.moveRight(nil)
        #expect(textView.selection == TextSelection(caret: 1))
        textView.moveRight(nil)
        #expect(textView.selection == TextSelection(caret: 3))
        textView.moveRight(nil)
        textView.moveRight(nil) // past the end: stays
        #expect(textView.selection == TextSelection(caret: 4))
        textView.moveLeft(nil)
        textView.moveLeft(nil)
        #expect(textView.selection == TextSelection(caret: 1))
    }

    @Test func verticalMovesKeepColumn() {
        let textView = view("abcdef\nab\nabcdef")
        textView.selection = TextSelection(caret: 4)   // line 0, column 4
        textView.moveDown(nil)
        #expect(textView.selection.head == 9)          // line 1 is short: clamps to its end
        textView.moveDown(nil)
        #expect(textView.selection.head == 14)         // line 2, column 4 again
        textView.moveUp(nil)
        textView.moveUp(nil)
        #expect(textView.selection.head == 4)
    }

    @Test func shiftExtendsAndPlainMoveCollapses() {
        let textView = view("hello world")
        textView.moveToEndOfLine(nil)
        #expect(textView.selection.head == 11)
        textView.moveLeftAndModifySelection(nil)
        textView.moveLeftAndModifySelection(nil)
        #expect(textView.selection == TextSelection(anchor: 11, head: 9))
        textView.moveLeft(nil)                          // collapses to the lower bound
        #expect(textView.selection == TextSelection(caret: 9))
        textView.moveToBeginningOfLineAndModifySelection(nil)
        #expect(textView.selection.range == 0..<9)
    }

    @Test func documentBoundsAndSelectAll() {
        let textView = view("one\ntwo\nthree")
        textView.moveToEndOfDocument(nil)
        #expect(textView.selection == TextSelection(caret: 13))
        textView.moveToBeginningOfDocument(nil)
        #expect(textView.selection == TextSelection(caret: 0))
        textView.selectAll(nil)
        #expect(textView.selection.range == 0..<13)
    }

    @Test func clickPlacesCaretAndDragExtends() {
        let textView = view("abc\ndef")
        let target = textView.layoutManager.caretRect(at: 5).offsetBy(dx: textView.textInset, dy: 0)
        textView.select(at: CGPoint(x: target.minX + 0.5, y: target.midY), extending: false)
        #expect(textView.selection == TextSelection(caret: 5))
        let origin = textView.layoutManager.caretRect(at: 1).offsetBy(dx: textView.textInset, dy: 0)
        textView.select(at: CGPoint(x: origin.minX + 0.5, y: origin.midY), extending: true)
        #expect(textView.selection == TextSelection(anchor: 5, head: 1))
    }

    @Test func typingIsIgnoredForNow() {
        let textView = view("abc")
        textView.insertText("x")
        #expect(textView.layoutManager.storage.string == "abc")
    }
}
