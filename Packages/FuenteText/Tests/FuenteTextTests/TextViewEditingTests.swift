import AppKit
import Testing
@testable import FuenteText

@Suite @MainActor struct TextViewEditingTests {
    final class Recorder: TextViewDelegate {
        var changes = 0
        func textViewDidChangeText(_ textView: TextView) { changes += 1 }
    }

    private let notFound = NSRange(location: NSNotFound, length: 0)

    private func view(_ text: String) -> TextView {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let textView = TextView(storage: TextStorage(text), typesetter: LineTypesetter(font: NSFont(name: "Menlo", size: 12)!))
        scrollView.documentView = textView
        scrollView.layoutSubtreeIfNeeded()
        return textView
    }

    private func type(_ text: String, into textView: TextView) {
        for character in text {
            textView.insertText(String(character), replacementRange: notFound)
        }
    }

    @Test func typingInsertsAtCaretAndReplacesSelection() {
        let textView = view("hello")
        textView.selection = TextSelection(caret: 5)
        type(" world", into: textView)
        #expect(textView.layoutManager.storage.string == "hello world")
        #expect(textView.selection == TextSelection(caret: 11))

        textView.selection = TextSelection(anchor: 0, head: 5)
        type("bye", into: textView)
        #expect(textView.layoutManager.storage.string == "bye world")
        #expect(textView.selection == TextSelection(caret: 3))
    }

    @Test func deadKeyComposesAccent() {
        let textView = view("caf")
        textView.selection = TextSelection(caret: 3)
        textView.setMarkedText("´", selectedRange: NSRange(location: 0, length: 1), replacementRange: notFound)
        #expect(textView.hasMarkedText())
        #expect(textView.layoutManager.storage.string == "caf´")
        #expect(textView.markedRange() == NSRange(location: 3, length: 1))

        textView.insertText("é", replacementRange: notFound)
        #expect(!textView.hasMarkedText())
        #expect(textView.layoutManager.storage.string == "café")
        #expect(textView.selection == TextSelection(caret: 4))
    }

    @Test func deleteBackwardRemovesWholeGrapheme() {
        let textView = view("a😀b")
        textView.selection = TextSelection(caret: 3)
        textView.deleteBackward(nil)
        #expect(textView.layoutManager.storage.string == "ab")
        #expect(textView.selection == TextSelection(caret: 1))
        textView.deleteBackward(nil)
        textView.deleteBackward(nil) // at start: no-op
        #expect(textView.layoutManager.storage.string == "b")
    }

    @Test func deleteForwardAndSelectionDelete() {
        let textView = view("abcdef")
        textView.deleteForward(nil)
        #expect(textView.layoutManager.storage.string == "bcdef")
        textView.selection = TextSelection(anchor: 1, head: 4)
        textView.deleteBackward(nil)
        #expect(textView.layoutManager.storage.string == "bf")
        #expect(textView.selection == TextSelection(caret: 1))
    }

    @Test func newlineSplitsLineAndLayoutFollows() {
        let textView = view("abcd")
        textView.selection = TextSelection(caret: 2)
        textView.insertNewline(nil)
        #expect(textView.layoutManager.storage.string == "ab\ncd")
        #expect(textView.layoutManager.lineCount == 2)
        #expect(textView.selection == TextSelection(caret: 3))
    }

    @Test func undoCoalescesTypingAndBreaksOnMovement() {
        let textView = view("")
        type("abc", into: textView)
        textView.moveLeft(nil)
        type("X", into: textView)
        #expect(textView.layoutManager.storage.string == "abXc")

        textView.undo(nil)
        #expect(textView.layoutManager.storage.string == "abc")
        textView.undo(nil)
        #expect(textView.layoutManager.storage.string == "")
        #expect(textView.selection == TextSelection(caret: 0))

        textView.redo(nil)
        #expect(textView.layoutManager.storage.string == "abc")
        textView.redo(nil)
        #expect(textView.layoutManager.storage.string == "abXc")
    }

    @Test func undoRestoresReplacedSelection() {
        let textView = view("hello world")
        textView.selection = TextSelection(anchor: 0, head: 5)
        type("bye", into: textView)
        textView.undo(nil)
        #expect(textView.layoutManager.storage.string == "hello world")
        #expect(textView.selection == TextSelection(anchor: 0, head: 5))
    }

    @Test func cutCopyPaste() {
        let textView = view("abc def")
        textView.pasteboard = NSPasteboard(name: NSPasteboard.Name("FuenteTests"))
        textView.selection = TextSelection(anchor: 0, head: 3)
        textView.copy(nil)
        #expect(textView.pasteboard.string(forType: .string) == "abc")

        textView.selection = TextSelection(caret: 7)
        textView.paste(nil)
        #expect(textView.layoutManager.storage.string == "abc defabc")

        textView.selection = TextSelection(anchor: 3, head: 7)
        textView.cut(nil)
        #expect(textView.layoutManager.storage.string == "abcabc")
        #expect(textView.pasteboard.string(forType: .string) == " def")
    }

    @Test func replaceAllSwapsContentAndClearsUndo() {
        let textView = view("old text here")
        type("x", into: textView)
        textView.selection = TextSelection(caret: 10)
        textView.replaceAll(with: "new")
        #expect(textView.layoutManager.storage.string == "new")
        #expect(textView.selection == TextSelection(caret: 3))
        textView.undo(nil)
        #expect(textView.layoutManager.storage.string == "new")
    }

    @Test func delegateIsNotifiedOnEveryChange() {
        let textView = view("")
        let recorder = Recorder()
        textView.delegate = recorder
        type("ab", into: textView)
        textView.deleteBackward(nil)
        textView.moveLeft(nil)
        #expect(recorder.changes == 3)
    }
}
