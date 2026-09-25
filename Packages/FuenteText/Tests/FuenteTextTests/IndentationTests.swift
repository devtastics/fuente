import AppKit
import Testing
@testable import FuenteText

@Suite @MainActor struct IndentationTests {
    private func view(_ text: String, caret: Int) -> TextView {
        let textView = TextView(storage: TextStorage(text), typesetter: LineTypesetter(font: NSFont(name: "Menlo", size: 12)!))
        textView.selection = TextSelection(caret: caret)
        return textView
    }

    @Test func tabInsertsTheIndentUnit() {
        let textView = view("", caret: 0)
        textView.insertTab(nil)
        #expect(textView.layoutManager.storage.string == "    ")
        textView.indentation = .tabs
        textView.insertTab(nil)
        #expect(textView.layoutManager.storage.string == "    \t")
        textView.indentation = .spaces(2)
        textView.insertTab(nil)
        #expect(textView.layoutManager.storage.string == "    \t  ")
    }

    @Test func newlineKeepsIndentation() {
        let textView = view("    return 1;", caret: 13)
        textView.insertNewline(nil)
        #expect(textView.layoutManager.storage.string == "    return 1;\n    ")
        #expect(textView.selection == TextSelection(caret: 18))
    }

    @Test func newlineAfterOpeningBracketAddsALevel() {
        let textView = view("if ($x) {", caret: 9)
        textView.insertNewline(nil)
        #expect(textView.layoutManager.storage.string == "if ($x) {\n    ")
        textView.indentation = .tabs
        let tabbed = view("\tfoo(", caret: 5)
        tabbed.indentation = .tabs
        tabbed.insertNewline(nil)
        #expect(tabbed.layoutManager.storage.string == "\tfoo(\n\t\t")
    }

    @Test func newlineInTheMiddleOfALineUsesTextBeforeTheCaret() {
        let textView = view("  ab", caret: 3)
        textView.insertNewline(nil)
        #expect(textView.layoutManager.storage.string == "  a\n  b")
        #expect(textView.selection == TextSelection(caret: 6))
    }

    @Test func newlineReplacesSelection() {
        let textView = view("  hello world", caret: 0)
        textView.selection = TextSelection(anchor: 7, head: 13)
        textView.insertNewline(nil)
        #expect(textView.layoutManager.storage.string == "  hello\n  ")
    }

    @Test func indentUnitText() {
        #expect(Indentation.tabs.unit == "\t")
        #expect(Indentation.spaces(2).unit == "  ")
        #expect(Indentation.spaces(0).unit == " ")
    }
}
