import Foundation

/// The document model of the text engine: UTF-16 code units in a gap buffer, plus the line starts layout needs.
///
/// Offsets and ranges are UTF-16, matching AppKit and CoreText. Lines are split on `\n` only.
public struct TextStorage: Sendable {
    private var buffer: GapBuffer

    /// UTF-16 offsets where each line starts. Always contains `0` and is strictly increasing.
    public private(set) var lineStarts: [Int]

    public init(_ string: String = "") {
        let units = Array(string.utf16)
        buffer = GapBuffer(units)
        lineStarts = TextStorage.lineStarts(in: units, base: 0)
    }

    /// The whole document as a String. Linear in the document size; prefer ranged access in hot paths.
    public var string: String {
        String(decoding: buffer.all, as: UTF16.self)
    }

    /// The whole document as UTF-16 code units, contiguous. What tree-sitter and CoreText consume.
    public var utf16Units: [UInt16] { buffer.all }

    public var utf16Count: Int { buffer.count }

    public var lineCount: Int { lineStarts.count }

    /// Zero-based line containing the given UTF-16 offset.
    public func line(at offset: Int) -> Int {
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// UTF-16 range of a line, excluding its trailing newline.
    public func lineRange(_ line: Int) -> Range<Int> {
        let start = lineStarts[line]
        let end = line + 1 < lineStarts.count ? lineStarts[line + 1] - 1 : utf16Count
        return start..<end
    }

    /// The text of a line, excluding its trailing newline.
    public func lineContent(_ line: Int) -> String {
        substring(lineRange(line))
    }

    public func substring(_ range: Range<Int>) -> String {
        String(decoding: buffer.copy(range), as: UTF16.self)
    }

    /// Offset of the next grapheme cluster boundary, or `offset` itself at the end of the document.
    public func offset(after offset: Int) -> Int {
        guard offset < utf16Count else { return offset }
        let range = lineRange(line(at: offset))
        guard offset < range.upperBound else { return offset + 1 } // step over the newline
        let content = substring(range)
        let index = content.utf16.index(content.utf16.startIndex, offsetBy: offset - range.lowerBound)
        return range.lowerBound + content.utf16.distance(from: content.utf16.startIndex, to: content.index(after: index))
    }

    /// Offset of the previous grapheme cluster boundary, or `0` at the start of the document.
    public func offset(before offset: Int) -> Int {
        guard offset > 0 else { return 0 }
        let range = lineRange(line(at: offset))
        guard offset > range.lowerBound else { return offset - 1 } // step over the newline
        let content = substring(range)
        let index = content.utf16.index(content.utf16.startIndex, offsetBy: offset - range.lowerBound)
        return range.lowerBound + content.utf16.distance(from: content.utf16.startIndex, to: content.index(before: index))
    }

    /// Line and column of an offset.
    public func point(at offset: Int) -> TextPoint {
        let row = line(at: offset)
        return TextPoint(row: row, column: offset - lineStarts[row])
    }

    /// Replaces a UTF-16 range with new text and updates line starts incrementally.
    /// Returns the edit in the form incremental parsers consume.
    @discardableResult
    public mutating func replace(_ range: Range<Int>, with replacement: String) -> TextEdit {
        precondition(range.lowerBound >= 0 && range.upperBound <= utf16Count, "range out of bounds")
        let units = Array(replacement.utf16)
        let startPoint = point(at: range.lowerBound)
        let oldEndPoint = point(at: range.upperBound)

        // Line starts strictly inside (lowerBound, upperBound] belong to newlines that are removed.
        let firstKept = line(at: range.lowerBound) + 1
        let firstAfter = line(at: range.upperBound) + 1
        let inserted = TextStorage.lineStarts(in: units, base: range.lowerBound).dropFirst()

        buffer.replace(range, with: units)

        let delta = units.count - range.count
        if delta != 0 {
            for index in firstAfter..<lineStarts.count {
                lineStarts[index] += delta
            }
        }
        lineStarts.replaceSubrange(firstKept..<firstAfter, with: inserted)

        let newEnd = range.lowerBound + units.count
        return TextEdit(
            start: range.lowerBound, oldEnd: range.upperBound, newEnd: newEnd,
            startPoint: startPoint, oldEndPoint: oldEndPoint, newEndPoint: point(at: newEnd)
        )
    }

    /// Line starts of `units`, offset by `base`. The first element is always `base`.
    private static func lineStarts(in units: [UInt16], base: Int) -> [Int] {
        var starts = [base]
        for (index, unit) in units.enumerated() where unit == 0x0A {
            starts.append(base + index + 1)
        }
        return starts
    }
}
