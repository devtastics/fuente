import Foundation

/// The document model of the text engine: a string plus the line boundaries needed for layout.
///
/// This is the seed of the engine. Layout, rendering and editing are built on top of it.
public struct TextStorage: Sendable {
    public private(set) var string: String

    /// UTF-16 offsets where each line starts. Always contains `0`.
    public private(set) var lineStarts: [Int]

    public init(_ string: String = "") {
        self.string = string
        self.lineStarts = TextStorage.computeLineStarts(string)
    }

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

    private static func computeLineStarts(_ string: String) -> [Int] {
        var starts = [0]
        var offset = 0
        for scalar in string.utf16 {
            offset += 1
            if scalar == 0x0A { starts.append(offset) }
        }
        return starts
    }
}
