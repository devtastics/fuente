import AppKit

/// A color applied to a UTF-16 range of the document. Produced by a highlighter, consumed by layout.
public struct StyledRange: Equatable {
    public var range: Range<Int>
    public var color: NSColor

    public init(range: Range<Int>, color: NSColor) {
        self.range = range
        self.color = color
    }
}
