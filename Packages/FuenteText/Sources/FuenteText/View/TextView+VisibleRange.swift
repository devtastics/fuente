import AppKit

extension TextView {
    /// UTF-16 range of the lines currently on screen, extended by `marginLines` above and below.
    /// Highlighters use it to color what the user can see and a little beyond.
    public func visibleCharacterRange(marginLines: Int = 0) -> Range<Int> {
        let storage = layoutManager.storage
        let visible = visibleRect
        let first = max(0, layoutManager.line(atY: max(0, visible.minY)) - marginLines)
        let last = min(storage.lineCount - 1, layoutManager.line(atY: max(0, visible.maxY - 1)) + marginLines)
        return storage.lineStarts[first]..<storage.lineRange(last).upperBound
    }
}
