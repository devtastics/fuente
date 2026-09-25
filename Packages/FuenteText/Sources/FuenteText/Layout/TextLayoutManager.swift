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

    /// Lines currently holding glyph runs; the rest sit on estimated heights.
    public private(set) var typesetLineCount = 0

    /// Colors over the document, sorted by start. `styleMaxEnds[i]` is the largest end among `styles[0...i]`,
    /// which lets the per-line lookup stop walking backwards as soon as no earlier style can reach the line.
    private var styles: [StyledRange] = []
    private var styleMaxEnds: [Int] = []

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

    // MARK: - Styles

    /// Replaces all colors. Keeps line heights: color does not change metrics, so only glyph runs are redone.
    public func setStyles(_ newStyles: [StyledRange]) {
        styles = newStyles.sorted { $0.range.lowerBound < $1.range.lowerBound }
        rebuildStyleIndex()
        invalidateLayoutsKeepingHeights()
    }

    private func rebuildStyleIndex() {
        styleMaxEnds.removeAll(keepingCapacity: true)
        var maxEnd = 0
        for style in styles {
            maxEnd = max(maxEnd, style.range.upperBound)
            styleMaxEnds.append(maxEnd)
        }
    }

    /// Styles intersecting a document range, clipped to it and made relative to `range.lowerBound`,
    /// in document order so nested (later-starting) styles override their containers.
    public func styles(in range: Range<Int>) -> [StyledRange] {
        guard !styles.isEmpty else { return [] }
        // First style starting at or after the end of the range: nothing from there on can intersect.
        var low = 0, high = styles.count
        while low < high {
            let mid = (low + high) / 2
            if styles[mid].range.lowerBound < range.upperBound { low = mid + 1 } else { high = mid }
        }
        var result: [StyledRange] = []
        var index = low - 1
        while index >= 0, styleMaxEnds[index] > range.lowerBound {
            let style = styles[index]
            if style.range.upperBound > range.lowerBound {
                let clipped = style.range.clamped(to: range)
                let local = (clipped.lowerBound - range.lowerBound)..<(clipped.upperBound - range.lowerBound)
                result.append(StyledRange(range: local, color: style.color))
            }
            index -= 1
        }
        result.reverse()
        return result
    }

    /// Keeps styles consistent with an edit until the highlighter catches up: drops styles touching
    /// the edited range and shifts the ones after it.
    private func adjustStyles(for range: Range<Int>, insertedLength: Int) {
        guard !styles.isEmpty else { return }
        let delta = insertedLength - range.count
        styles = styles.compactMap { style in
            if style.range.upperBound <= range.lowerBound { return style }
            if style.range.lowerBound >= range.upperBound {
                return StyledRange(range: (style.range.lowerBound + delta)..<(style.range.upperBound + delta), color: style.color)
            }
            return nil
        }
        rebuildStyleIndex()
    }

    /// Drops glyph runs but keeps heights. For color-only changes, such as highlighting or appearance.
    public func invalidateLayoutsKeepingHeights() {
        layouts = Array(repeating: nil, count: storage.lineCount)
        typesetLineCount = 0
    }

    /// Fragments of a line, typesetting it now if it has none.
    @discardableResult
    public func ensureLayout(_ line: Int) -> [LineFragment] {
        if let existing = layouts[line] { return existing }
        let fragments = typesetter.typeset(storage.lineContent(line), styles: styles(in: storage.lineRange(line)), width: wrapWidth)
        let height = fragments.reduce(0) { $0 + $1.height }
        heights.add(height - self.height(ofLine: line), at: line)
        contentWidth = max(contentWidth, fragments.map(\.width).max() ?? 0)
        layouts[line] = fragments
        typesetLineCount += 1
        return fragments
    }

    // MARK: - Geometry

    /// Rectangle of a caret placed before the character at `offset`, in text coordinates (no insets).
    public func caretRect(at offset: Int) -> CGRect {
        let line = storage.line(at: offset)
        let fragments = ensureLayout(line)
        let local = offset - storage.lineStarts[line]
        var y = yOffset(ofLine: line)
        for fragment in fragments {
            let isLast = fragment === fragments.last
            if fragment.range.contains(local) || (isLast && local >= fragment.range.upperBound) {
                return CGRect(x: fragment.xOffset(for: local), y: y, width: 1, height: fragment.height)
            }
            y += fragment.height
        }
        return CGRect(x: 0, y: y, width: 1, height: estimatedLineHeight)
    }

    /// Offset closest to a point in text coordinates. Points above the document map to `0`, below it to the end.
    public func offset(at point: CGPoint) -> Int {
        guard point.y >= 0 else { return 0 }
        guard point.y < contentHeight else { return storage.utf16Count }
        let line = line(atY: point.y)
        let fragments = ensureLayout(line)
        var y = yOffset(ofLine: line)
        var chosen = fragments[fragments.count - 1]
        for fragment in fragments {
            if point.y < y + fragment.height { chosen = fragment; break }
            y += fragment.height
        }
        let local = min(chosen.offset(forX: point.x), chosen.range.upperBound)
        return storage.lineStarts[line] + local
    }

    /// Rectangles covering a range, one per fragment row it touches, in text coordinates.
    /// Rows where the range continues past the end of the row get `newlineWidth` extra to show it.
    public func selectionRects(for range: Range<Int>, newlineWidth: CGFloat = 6) -> [CGRect] {
        guard !range.isEmpty else { return [] }
        var rects: [CGRect] = []
        let firstLine = storage.line(at: range.lowerBound)
        let lastLine = storage.line(at: range.upperBound)
        for line in firstLine...lastLine {
            let fragments = ensureLayout(line)
            let lineStart = storage.lineStarts[line]
            let lineEnd = storage.lineRange(line).upperBound
            var y = yOffset(ofLine: line)
            for fragment in fragments {
                let rowStart = lineStart + fragment.range.lowerBound
                let rowEnd = lineStart + fragment.range.upperBound
                let from = max(range.lowerBound, rowStart)
                let to = min(range.upperBound, rowEnd)
                defer { y += fragment.height }
                guard from <= to, from < rowEnd || (from == rowEnd && rowEnd == lineEnd && range.upperBound > lineEnd) else { continue }
                var x1 = fragment.xOffset(for: from - lineStart)
                var x2 = fragment.xOffset(for: to - lineStart)
                if x2 < x1 { swap(&x1, &x2) }
                let continuesPastRow = range.upperBound > rowEnd && rowEnd == lineEnd
                rects.append(CGRect(x: x1, y: y, width: x2 - x1 + (continuesPastRow ? newlineWidth : 0), height: fragment.height))
            }
        }
        return rects
    }

    /// Edits the text and invalidates the lines the edit touched.
    @discardableResult
    public func replace(_ range: Range<Int>, with text: String) -> TextEdit {
        let firstLine = storage.line(at: range.lowerBound)
        let lastOldLine = storage.line(at: range.upperBound)
        let edit = storage.replace(range, with: text)
        adjustStyles(for: range, insertedLength: text.utf16.count)
        let lastNewLine = storage.line(at: range.lowerBound + text.utf16.count)

        let replacement = [[LineFragment]?](repeating: nil, count: lastNewLine - firstLine + 1)
        if replacement.count == lastOldLine - firstLine + 1 {
            for line in firstLine...lastOldLine { invalidate(line) }
        } else {
            layouts.replaceSubrange(firstLine...lastOldLine, with: replacement)
            typesetLineCount = layouts.lazy.filter { $0 != nil }.count
            rebuildHeights()
        }
        return edit
    }

    private func invalidate(_ line: Int) {
        guard layouts[line] != nil else { return }
        layouts[line] = nil
        typesetLineCount -= 1
        heights.add(estimatedLineHeight - height(ofLine: line), at: line)
    }

    private func invalidateAllLines() {
        layouts = Array(repeating: nil, count: storage.lineCount)
        typesetLineCount = 0
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
