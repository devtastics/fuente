import TreeSitter

struct QueryMatch {
    let patternIndex: Int
    let captures: [(index: Int, node: Node)]
}

/// Iterates the matches of a query over a node. Not thread-safe.
final class QueryCursor {
    private let pointer: OpaquePointer

    init() { pointer = ts_query_cursor_new() }
    deinit { ts_query_cursor_delete(pointer) }

    func execute(_ query: Query, on node: Node, utf16Range: Range<Int>? = nil) {
        if let utf16Range {
            ts_query_cursor_set_byte_range(pointer, UInt32(utf16Range.lowerBound * 2), UInt32(utf16Range.upperBound * 2))
        }
        ts_query_cursor_exec(pointer, query.pointer, node.raw)
    }

    func nextMatch() -> QueryMatch? {
        var match = TSQueryMatch()
        guard ts_query_cursor_next_match(pointer, &match) else { return nil }
        let captures = (0..<Int(match.capture_count)).map { index in
            let capture = match.captures[index]
            return (index: Int(capture.index), node: Node(capture.node))
        }
        return QueryMatch(patternIndex: Int(match.pattern_index), captures: captures)
    }
}
