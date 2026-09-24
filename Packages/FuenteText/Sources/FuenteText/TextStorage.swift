import Foundation

/// The document model of the text engine: a string plus the line boundaries needed for layout.
///
/// Offsets and ranges are UTF-16, matching AppKit and CoreText. Lines are split on `\n` only.
public struct TextStorage: Sendable {
    public private(set) var string: String

    /// UTF-16 offsets where each line starts. Always contains `0` and is strictly increasing.
    public private(set) var lineStarts: [Int]

    public init(_ string: String = "") {
        self.string = string
        self.lineStarts = TextStorage.lineStarts(in: string, base: 0)
    }

    public var utf16Count: Int { string.utf16.count }

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
        String(substring(lineRange(line)))
    }

    public func substring(_ range: Range<Int>) -> Substring {
        let utf16 = string.utf16
        let start = utf16.index(utf16.startIndex, offsetBy: range.lowerBound)
        let end = utf16.index(start, offsetBy: range.count)
        return string[start..<end]
    }

    /// Replaces a UTF-16 range with new text and updates line starts incrementally.
    public mutating func replace(_ range: Range<Int>, with replacement: String) {
        precondition(range.lowerBound >= 0 && range.upperBound <= utf16Count, "range out of bounds")

        let utf16 = string.utf16
        let start = utf16.index(utf16.startIndex, offsetBy: range.lowerBound)
        let end = utf16.index(start, offsetBy: range.count)
        string.replaceSubrange(start..<end, with: replacement)

        // Line starts strictly inside (lowerBound, upperBound] belong to newlines that were removed.
        let firstKept = line(at: range.lowerBound) + 1
        let firstAfter = line(at: range.upperBound) + 1
        let inserted = TextStorage.lineStarts(in: replacement, base: range.lowerBound).dropFirst()

        let delta = replacement.utf16.count - range.count
        if delta != 0 {
            for index in firstAfter..<lineStarts.count {
                lineStarts[index] += delta
            }
        }
        lineStarts.replaceSubrange(firstKept..<firstAfter, with: inserted)
    }

    /// Line starts of `string`, offset by `base`. The first element is always `base`.
    private static func lineStarts(in string: String, base: Int) -> [Int] {
        var starts = [base]
        var offset = base
        for unit in string.utf16 {
            offset += 1
            if unit == 0x0A { starts.append(offset) }
        }
        return starts
    }
}
