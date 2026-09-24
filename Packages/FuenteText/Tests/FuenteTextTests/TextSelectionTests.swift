import Testing
@testable import FuenteText

@Suite struct TextSelectionTests {
    @Test func caretIsEmpty() {
        let selection = TextSelection(caret: 4)
        #expect(selection.isEmpty)
        #expect(selection.range == 4..<4)
    }

    @Test func rangeIsNormalized() {
        #expect(TextSelection(anchor: 7, head: 2).range == 2..<7)
        #expect(TextSelection(anchor: 2, head: 7).range == 2..<7)
    }
}
