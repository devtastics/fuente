import Testing
@testable import FuenteText

@Suite struct TextStorageEditTests {
    /// Every edit must leave `lineStarts` identical to recomputing them from scratch.
    private func check(_ storage: TextStorage) {
        #expect(storage.lineStarts == TextStorage(storage.string).lineStarts)
    }

    @Test func insertNewlineSplitsLine() {
        var storage = TextStorage("hello world")
        storage.replace(5..<6, with: "\n")
        #expect(storage.string == "hello\nworld")
        #expect(storage.lineStarts == [0, 6])
        check(storage)
    }

    @Test func deleteAcrossLinesMergesThem() {
        var storage = TextStorage("a\nb\nc\nd")
        storage.replace(1..<5, with: "")
        #expect(storage.string == "a\nd")
        #expect(storage.lineStarts == [0, 2])
        check(storage)
    }

    @Test func replaceWithMultilineText() {
        var storage = TextStorage("<?php\n\necho 1;")
        storage.replace(6..<6, with: "use Foo;\nuse Bar;\n")
        #expect(storage.lineCount == 5)
        #expect(storage.lineContent(1) == "use Foo;")
        #expect(storage.lineContent(4) == "echo 1;")
        check(storage)
    }

    @Test func editSequenceMatchesRecomputation() {
        var storage = TextStorage("")
        let edits: [(Range<Int>, String)] = [
            (0..<0, "function f() {\n    return 1;\n}\n"),
            (14..<14, "\n"),          // newline right after "{"
            (0..<9, "fn"),            // replace "function " keeping the rest
            (8..<10, ""),             // delete the newline just inserted
            (20..<21, "\n\n\n"),      // one char into three newlines
        ]
        for (range, text) in edits {
            storage.replace(range, with: text)
            check(storage)
        }
        storage.replace(0..<storage.utf16Count, with: "x")
        check(storage)
        #expect(storage.string == "x")
        #expect(storage.lineStarts == [0])
    }

    @Test func lineRangesExcludeNewline() {
        let storage = TextStorage("ab\ncd\n")
        #expect(storage.lineRange(0) == 0..<2)
        #expect(storage.lineRange(1) == 3..<5)
        #expect(storage.lineRange(2) == 6..<6)
        #expect(storage.lineContent(1) == "cd")
    }
}
