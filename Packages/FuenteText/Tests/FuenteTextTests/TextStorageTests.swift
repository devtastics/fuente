import Testing
@testable import FuenteText

@Suite struct TextStorageTests {
    @Test func emptyDocumentHasOneLine() {
        let storage = TextStorage()
        #expect(storage.lineCount == 1)
        #expect(storage.line(at: 0) == 0)
    }

    @Test func lineStartsFollowNewlines() {
        let storage = TextStorage("<?php\necho 1;\n")
        #expect(storage.lineStarts == [0, 6, 14])
        #expect(storage.lineCount == 3)
    }

    @Test func lineLookupByOffset() {
        let storage = TextStorage("ab\ncd\nef")
        #expect(storage.line(at: 0) == 0)
        #expect(storage.line(at: 2) == 0)
        #expect(storage.line(at: 3) == 1)
        #expect(storage.line(at: 7) == 2)
    }
}
