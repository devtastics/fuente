import Foundation

/// UTF-16 code units with a movable gap at the edit point: typing writes into the gap without shifting the
/// rest of the document. Moving the gap costs the distance moved; growing it happens rarely and is amortized.
struct GapBuffer: Sendable {
    private var units: [UInt16]
    private var gapStart: Int
    private var gapEnd: Int

    init(_ units: [UInt16]) {
        self.units = units
        gapStart = units.count
        gapEnd = units.count
    }

    var count: Int { units.count - (gapEnd - gapStart) }

    subscript(index: Int) -> UInt16 {
        index < gapStart ? units[index] : units[index + gapEnd - gapStart]
    }

    /// The units of a range, contiguous.
    func copy(_ range: Range<Int>) -> [UInt16] {
        var result = [UInt16]()
        result.reserveCapacity(range.count)
        let beforeGap = max(0, min(range.upperBound, gapStart) - range.lowerBound)
        if beforeGap > 0 {
            result.append(contentsOf: units[range.lowerBound..<(range.lowerBound + beforeGap)])
        }
        let afterStart = max(range.lowerBound, gapStart)
        if afterStart < range.upperBound {
            let gap = gapEnd - gapStart
            result.append(contentsOf: units[(afterStart + gap)..<(range.upperBound + gap)])
        }
        return result
    }

    var all: [UInt16] { copy(0..<count) }

    /// The text as two contiguous runs, before and after the gap. Valid only inside `body`.
    func withSegments<R>(_ body: (UnsafeBufferPointer<UInt16>, UnsafeBufferPointer<UInt16>) throws -> R) rethrows -> R {
        try units.withUnsafeBufferPointer { buffer in
            let prefix = UnsafeBufferPointer(rebasing: buffer[0..<gapStart])
            let suffix = UnsafeBufferPointer(rebasing: buffer[gapEnd..<buffer.count])
            return try body(prefix, suffix)
        }
    }

    mutating func replace(_ range: Range<Int>, with new: [UInt16]) {
        moveGap(to: range.lowerBound)
        gapEnd += range.count // deleted units become part of the gap
        let free = gapEnd - gapStart
        if new.count > free {
            grow(by: max(new.count - free, count / 2, 1024))
        }
        units.withUnsafeMutableBufferPointer { buffer in
            new.withUnsafeBufferPointer { source in
                guard let base = buffer.baseAddress, let from = source.baseAddress, !new.isEmpty else { return }
                (base + gapStart).update(from: from, count: new.count)
            }
        }
        gapStart += new.count
    }

    private mutating func moveGap(to position: Int) {
        guard position != gapStart else { return }
        let gap = gapEnd - gapStart
        units.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            if position < gapStart {
                // Slide [position, gapStart) right, to the end of the gap.
                let moved = gapStart - position
                memmove(base + gapEnd - moved, base + position, moved * 2)
            } else {
                // Slide [gapEnd, gapEnd + moved) left, to the start of the gap.
                let moved = position - gapStart
                memmove(base + gapStart, base + gapEnd, moved * 2)
            }
        }
        gapStart = position
        gapEnd = position + gap
    }

    private mutating func grow(by extra: Int) {
        units.insert(contentsOf: repeatElement(0, count: extra), at: gapEnd)
        gapEnd += extra
    }
}
