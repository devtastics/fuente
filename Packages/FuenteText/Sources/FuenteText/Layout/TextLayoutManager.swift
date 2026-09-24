import AppKit

/// A line placed vertically, with its fragments, as returned to the view for drawing.
public struct LaidOutLine {
    public let index: Int
    public let y: CGFloat
    public let height: CGFloat
    public let fragments: [LineFragment]
}

/// Places lines vertically and typesets them lazily.
///
/// Lines that have not been drawn yet use an estimated height, so opening a large document
/// costs one pass over the line starts and nothing else. Real heights replace estimates as
/// lines come into view. All edits go through `replace(_:with:)` so affected lines are invalidated.
@MainActor
public final class TextLayoutManager {
    public private(set) var storage: TextStorage

    public var typesetter: LineTypesetter {
        didSet { invalidateAllLines() }
    }

    /// Width to wrap lines at. `nil` disables wrapping.
    public var wrapWidth: CGFloat? {
        didSet { if wrapWidth != oldValue { invalidateAllLines() } }
    }

    /// Height used for lines not typeset yet: one row of the current font.
    public var estimatedLineHeight: CGFloat {
        typesetter.typeset("").first?.height ?? 0
    }

    /// Height of the whole document with current estimates.
    public var contentHeight: CGFloat { heights.total }

    /// Widest line typeset so far. Never shrinks until all lines are invalidated.
    public private(set) var contentWidth: CGFloat = 0

    private var layouts: [[LineFragment]?]
    private var heights: PrefixSumTree

    public init(storage: TextStorage, typesetter: LineTypesetter = LineTypesetter(), wrapWidth: CGFloat? = nil) {
        self.storage = storage
        self.typesetter = typesetter
        self.wrapWidth = wrapWidth
        self.layouts = Array(repeating: nil, count: storage.lineCount)
        self.heights = PrefixSumTree([])
        rebuildHeights()
    }

    public var lineCount: Int { storage.lineCount }

    public func isLaidOut(_ line: Int) -> Bool { layouts[line] != nil }

    public func yOffset(ofLine line: Int) -> CGFloat { heights.sum(upTo: line) }

    public func height(ofLine line: Int) -> CGFloat {
        heights.sum(upTo: line + 1) - heights.sum(upTo: line)
    }

    public func line(atY y: CGFloat) -> Int { heights.index(containing: y) }

    /// Typesets, if needed, and returns every line intersecting `rect`.
    public func layoutLines(in rect: CGRect) -> [LaidOutLine] {
        var result: [LaidOutLine] = []
        var line = self.line(atY: rect.minY)
        while line < lineCount {
            let y = yOffset(ofLine: line)
            guard y < rect.maxY else { break }
            let fragments = ensureLayout(line)
            result.append(LaidOutLine(index: line, y: y, height: height(ofLine: line), fragments: fragments))
            line += 1
        }
        return result
    }

    /// Fragments of a line, typesetting it now if it has none.
    @discardableResult
    public func ensureLayout(_ line: Int) -> [LineFragment] {
        if let existing = layouts[line] { return existing }
        let fragments = typesetter.typeset(storage.lineContent(line), width: wrapWidth)
        let height = fragments.reduce(0) { $0 + $1.height }
        heights.add(height - self.height(ofLine: line), at: line)
        contentWidth = max(contentWidth, fragments.map(\.width).max() ?? 0)
        layouts[line] = fragments
        return fragments
    }

    /// Edits the text and invalidates the lines the edit touched.
    public func replace(_ range: Range<Int>, with text: String) {
        let firstLine = storage.line(at: range.lowerBound)
        let lastOldLine = storage.line(at: range.upperBound)
        storage.replace(range, with: text)
        let lastNewLine = storage.line(at: range.lowerBound + text.utf16.count)

        let replacement = [[LineFragment]?](repeating: nil, count: lastNewLine - firstLine + 1)
        if replacement.count == lastOldLine - firstLine + 1 {
            for line in firstLine...lastOldLine { invalidate(line) }
        } else {
            layouts.replaceSubrange(firstLine...lastOldLine, with: replacement)
            rebuildHeights()
        }
    }

    private func invalidate(_ line: Int) {
        guard layouts[line] != nil else { return }
        layouts[line] = nil
        heights.add(estimatedLineHeight - height(ofLine: line), at: line)
    }

    private func invalidateAllLines() {
        layouts = Array(repeating: nil, count: storage.lineCount)
        contentWidth = 0
        rebuildHeights()
    }

    /// Rebuilds the height tree from cached layouts, using the estimate for lines without one.
    private func rebuildHeights() {
        let estimate = estimatedLineHeight
        heights = PrefixSumTree(layouts.map { fragments in
            fragments.map { $0.reduce(0) { $0 + $1.height } } ?? estimate
        })
    }
}
