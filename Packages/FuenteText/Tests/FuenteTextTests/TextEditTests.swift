import Testing
@testable import FuenteText

@Suite struct TextEditTests {
    @Test func replaceDescribesTheEditWithPoints() {
        var storage = TextStorage("ab\ncd\nef")
        let edit = storage.replace(4..<7, with: "X\nYZ")   // replaces "d\ne" with "X\nYZ"
        #expect(storage.string == "ab\ncX\nYZf")
        #expect(edit.start == 4 && edit.oldEnd == 7 && edit.newEnd == 8)
        #expect(edit.startPoint == TextPoint(row: 1, column: 1))
        #expect(edit.oldEndPoint == TextPoint(row: 2, column: 1))
        #expect(edit.newEndPoint == TextPoint(row: 2, column: 2))
    }

    @Test func insertionAtEndOfDocument() {
        var storage = TextStorage("abc")
        let edit = storage.replace(3..<3, with: "\n")
        #expect(edit.oldEndPoint == TextPoint(row: 0, column: 3))
        #expect(edit.newEndPoint == TextPoint(row: 1, column: 0))
        #expect(storage.point(at: 4) == TextPoint(row: 1, column: 0))
    }
}
