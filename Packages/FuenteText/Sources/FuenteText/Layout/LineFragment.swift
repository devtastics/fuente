import CoreText
import Foundation

/// One visual row of a line: the whole line when it fits, or a piece of it when wrapped.
///
/// Wraps a `CTLine` and its typographic metrics. Not `Sendable`: fragments belong to the
/// layout pass that created them and are used from the same isolation domain.
public final class LineFragment {
    public let ctLine: CTLine

    /// UTF-16 range within the line this fragment renders.
    public let range: Range<Int>

    public let width: CGFloat
    public let ascent: CGFloat
    public let descent: CGFloat
    public let leading: CGFloat

    public var height: CGFloat { ceil(ascent + descent + leading) }

    init(ctLine: CTLine, range: Range<Int>, width: CGFloat, ascent: CGFloat, descent: CGFloat, leading: CGFloat) {
        self.ctLine = ctLine
        self.range = range
        self.width = width
        self.ascent = ascent
        self.descent = descent
        self.leading = leading
    }

    /// Horizontal position of a UTF-16 offset within the line, relative to the fragment's origin.
    public func xOffset(for offset: Int) -> CGFloat {
        CTLineGetOffsetForStringIndex(ctLine, offset, nil)
    }

    /// UTF-16 offset within the line closest to a horizontal position relative to the fragment's origin.
    public func offset(forX x: CGFloat) -> Int {
        let index = CTLineGetStringIndexForPosition(ctLine, CGPoint(x: x, y: 0))
        return index == kCFNotFound ? range.upperBound : index
    }
}
