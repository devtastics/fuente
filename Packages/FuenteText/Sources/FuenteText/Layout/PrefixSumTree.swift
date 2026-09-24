import Foundation

/// Fenwick tree over line heights: O(log n) height updates, prefix sums and lookup by y.
///
/// Fixed size. When the number of lines changes the owner rebuilds it, which is O(n) but a
/// plain array pass; fast enough until profiling says otherwise.
struct PrefixSumTree {
    private var tree: [CGFloat]
    let count: Int

    init(_ values: [CGFloat]) {
        count = values.count
        tree = [0] + values
        for index in 1..<tree.count {
            let parent = index + (index & -index)
            if parent < tree.count { tree[parent] += tree[index] }
        }
    }

    mutating func add(_ delta: CGFloat, at index: Int) {
        var node = index + 1
        while node <= count {
            tree[node] += delta
            node += node & -node
        }
    }

    /// Sum of values in `0..<index`.
    func sum(upTo index: Int) -> CGFloat {
        var node = index, sum: CGFloat = 0
        while node > 0 {
            sum += tree[node]
            node -= node & -node
        }
        return sum
    }

    var total: CGFloat { sum(upTo: count) }

    /// Index whose range `[sum(upTo: i), sum(upTo: i + 1))` contains `value`, clamped to valid indices.
    func index(containing value: CGFloat) -> Int {
        guard count > 0, value > 0 else { return 0 }
        var position = 0, remaining = value
        var step = 1
        while step * 2 <= count { step *= 2 }
        while step > 0 {
            let next = position + step
            if next <= count && tree[next] <= remaining {
                position = next
                remaining -= tree[next]
            }
            step /= 2
        }
        return min(position, count - 1)
    }
}
