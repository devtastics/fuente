import AppKit
import Testing
@testable import FuenteText

@Suite @MainActor struct LayoutGeometryTests {
    let typesetter = LineTypesetter(font: NSFont(name: "Menlo", size: 12)!)

    private func manager(_ text: String, wrapWidth: CGFloat? = nil) -> TextLayoutManager {
        TextLayoutManager(storage: TextStorage(text), typesetter: typesetter, wrapWidth: wrapWidth)
    }

    @Test func caretRectsAdvanceAlongTheLineAndDownTheDocument() {
        let manager = manager("abc\ndef")
        let a = manager.caretRect(at: 0), b = manager.caretRect(at: 1), d = manager.caretRect(at: 4)
        #expect(a.minX == 0 && a.minY == 0)
        #expect(b.minX > a.minX && b.minY == a.minY)
        #expect(d.minX == 0 && d.minY == a.maxY)
        #expect(manager.caretRect(at: 3).minX > b.minX) // end of first line
    }

    @Test func pointRoundTripsToOffset() {
        let manager = manager("hello\nworld\n\nend")
        for offset in 0...manager.storage.utf16Count {
            let rect = manager.caretRect(at: offset)
            let point = CGPoint(x: rect.minX + 0.5, y: rect.midY)
            #expect(manager.offset(at: point) == offset, "offset \(offset)")
        }
    }

    @Test func pointsOutsideDocumentClamp() {
        let manager = manager("ab\ncd")
        #expect(manager.offset(at: CGPoint(x: 10, y: -50)) == 0)
        #expect(manager.offset(at: CGPoint(x: 10, y: 10_000)) == 5)
        #expect(manager.offset(at: CGPoint(x: 10_000, y: 1)) == 2) // far right of line 0 -> its end
    }

    @Test func wrappedLinePlacesCaretOnSecondRow() {
        let manager = manager(String(repeating: "x", count: 40), wrapWidth: 100)
        let fragments = manager.ensureLayout(0)
        #expect(fragments.count > 1)
        let secondRowStart = fragments[1].range.lowerBound
        let rect = manager.caretRect(at: secondRowStart)
        #expect(rect.minY == fragments[0].height)
        #expect(rect.minX == 0)
        #expect(manager.offset(at: CGPoint(x: 0.5, y: rect.midY)) == secondRowStart)
    }

    @Test func selectionRectsCoverEachRowTouched() {
        let manager = manager("abc\ndef\nghi")
        let single = manager.selectionRects(for: 1..<2)
        #expect(single.count == 1)
        #expect(single[0].minX == manager.caretRect(at: 1).minX)
        #expect(single[0].maxX == manager.caretRect(at: 2).minX)

        let multi = manager.selectionRects(for: 1..<9) // "bc\ndef\ng"
        #expect(multi.count == 3)
        #expect(multi[0].maxX > manager.caretRect(at: 3).minX) // includes newline marker
        #expect(multi[1].minX == 0)
        #expect(multi[2].minX == 0 && multi[2].maxX == manager.caretRect(at: 9).minX)
        #expect(manager.selectionRects(for: 2..<2).isEmpty)
    }
}
