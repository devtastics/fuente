import AppKit
import Testing
@testable import FuenteText

@Suite @MainActor struct TextLayoutManagerTests {
    let typesetter = LineTypesetter(font: NSFont(name: "Menlo", size: 12)!)

    private func manager(_ text: String, wrapWidth: CGFloat? = nil) -> TextLayoutManager {
        TextLayoutManager(storage: TextStorage(text), typesetter: typesetter, wrapWidth: wrapWidth)
    }

    @Test func startsWithEstimatesAndNoLayout() {
        let manager = manager("a\nb\nc\nd")
        let estimate = manager.estimatedLineHeight
        #expect(estimate > 0)
        #expect(manager.contentHeight == estimate * 4)
        #expect((0..<4).allSatisfy { !manager.isLaidOut($0) })
        #expect(manager.yOffset(ofLine: 2) == estimate * 2)
    }

    @Test func layoutOnlyTouchesVisibleLines() {
        let manager = manager((0..<100).map(String.init).joined(separator: "\n"))
        let estimate = manager.estimatedLineHeight
        let visible = manager.layoutLines(in: CGRect(x: 0, y: estimate * 10, width: 500, height: estimate * 3))

        #expect(visible.map(\.index) == [10, 11, 12])
        #expect(manager.isLaidOut(10) && manager.isLaidOut(12))
        #expect(!manager.isLaidOut(9) && !manager.isLaidOut(13))
        #expect(visible[0].y == estimate * 10)
        #expect(manager.contentWidth > 0)
    }

    @Test func wrappedLinePushesFollowingLinesDown() {
        let long = String(repeating: "x", count: 200)
        let manager = manager("first\n\(long)\nlast", wrapWidth: 100)
        let estimate = manager.estimatedLineHeight

        _ = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 100, height: 10_000))
        let wrappedHeight = manager.height(ofLine: 1)
        #expect(wrappedHeight > estimate * 2)
        #expect(manager.yOffset(ofLine: 2) == estimate + wrappedHeight)
        #expect(manager.line(atY: estimate + wrappedHeight / 2) == 1)
        #expect(manager.line(atY: estimate + wrappedHeight) == 2)
        #expect(manager.contentHeight == estimate * 2 + wrappedHeight)
    }

    @Test func editInvalidatesOnlyTouchedLines() {
        let manager = manager("aaa\nbbb\nccc")
        _ = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 10_000))
        #expect((0..<3).allSatisfy { manager.isLaidOut($0) })

        manager.replace(4..<5, with: "B")
        #expect(manager.storage.lineContent(1) == "Bbb")
        #expect(manager.isLaidOut(0) && !manager.isLaidOut(1) && manager.isLaidOut(2))
    }

    @Test func insertingNewlineAddsALine() {
        let manager = manager("aaa\nbbb")
        let estimate = manager.estimatedLineHeight
        _ = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 10_000))

        manager.replace(1..<1, with: "\n")
        #expect(manager.lineCount == 3)
        #expect(manager.storage.lineContent(0) == "a")
        #expect(manager.storage.lineContent(1) == "aa")
        #expect(!manager.isLaidOut(0) && !manager.isLaidOut(1) && manager.isLaidOut(2))
        #expect(manager.contentHeight == estimate * 3)
    }

    @Test func deletingAcrossLinesRemovesLines() {
        let manager = manager("a\nb\nc\nd")
        _ = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 10_000))
        manager.replace(1..<5, with: "")
        #expect(manager.lineCount == 2)
        #expect(manager.storage.string == "a\nd")
        #expect(!manager.isLaidOut(0) && manager.isLaidOut(1))
        #expect(manager.contentHeight == manager.estimatedLineHeight * 2)
    }

    @Test func changingWrapWidthInvalidatesEverything() {
        let manager = manager("aaa\nbbb")
        _ = manager.layoutLines(in: CGRect(x: 0, y: 0, width: 500, height: 10_000))
        manager.wrapWidth = 50
        #expect(!manager.isLaidOut(0) && !manager.isLaidOut(1))
        #expect(manager.contentWidth == 0)
    }
}
