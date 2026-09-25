import FuenteText
import TreeSitter

/// Owns a `TSParser`. Not thread-safe: use from one isolation domain.
final class Parser {
    private let pointer: OpaquePointer

    init(language: Language) {
        pointer = ts_parser_new()
        precondition(ts_parser_set_language(pointer, language.pointer), "grammar ABI incompatible with tree-sitter runtime")
    }

    deinit { ts_parser_delete(pointer) }

    /// Restricts parsing to these UTF-16 ranges (sorted, non-overlapping), treated as one contiguous text.
    /// `nil` parses the whole document again.
    func setIncludedRanges(_ ranges: [Range<Int>]?, in storage: TextStorage) {
        guard let ranges, !ranges.isEmpty else {
            ts_parser_set_included_ranges(pointer, nil, 0)
            return
        }
        var tsRanges = ranges.map { range -> TSRange in
            let start = storage.point(at: range.lowerBound), end = storage.point(at: range.upperBound)
            return TSRange(
                start_point: TSPoint(row: UInt32(start.row), column: UInt32(start.column * 2)),
                end_point: TSPoint(row: UInt32(end.row), column: UInt32(end.column * 2)),
                start_byte: UInt32(range.lowerBound * 2), end_byte: UInt32(range.upperBound * 2)
            )
        }
        let accepted = tsRanges.withUnsafeMutableBufferPointer { ts_parser_set_included_ranges(pointer, $0.baseAddress, UInt32($0.count)) }
        precondition(accepted, "included ranges must be sorted and non-overlapping")
    }

    /// Parses UTF-16 code units. `oldTree` must have been edited to match `text` first; pass `nil` for a full parse.
    func parse(_ text: [UInt16], oldTree: Tree? = nil) -> Tree? {
        let raw = text.withUnsafeBufferPointer { buffer -> OpaquePointer? in
            guard let base = buffer.baseAddress else {
                return ts_parser_parse_string_encoding(pointer, oldTree?.pointer, "", 0, TSInputEncodingUTF16LE)
            }
            return base.withMemoryRebound(to: CChar.self, capacity: buffer.count * 2) { bytes in
                ts_parser_parse_string_encoding(pointer, oldTree?.pointer, bytes, UInt32(buffer.count * 2), TSInputEncodingUTF16LE)
            }
        }
        return raw.map(Tree.init)
    }

    /// Parses a `TextStorage` in place: tree-sitter reads the two runs of the gap buffer through a callback,
    /// so nothing is copied. `oldTree` must have been edited to match; pass `nil` for a full parse.
    func parse(_ storage: TextStorage, oldTree: Tree? = nil) -> Tree? {
        storage.withUTF16Segments { prefix, suffix in
            var segments = Segments(
                prefix: UnsafeRawPointer(prefix.baseAddress), prefixBytes: prefix.count * 2,
                suffix: UnsafeRawPointer(suffix.baseAddress), suffixBytes: suffix.count * 2
            )
            return withUnsafeMutablePointer(to: &segments) { payload -> Tree? in
                let input = TSInput(payload: payload, read: readSegments, encoding: TSInputEncodingUTF16LE, decode: nil)
                return ts_parser_parse(pointer, oldTree?.pointer, input).map(Tree.init)
            }
        }
    }
}

/// Two contiguous byte runs handed to tree-sitter's read callback.
private struct Segments {
    var prefix: UnsafeRawPointer?
    var prefixBytes: Int
    var suffix: UnsafeRawPointer?
    var suffixBytes: Int
}

nonisolated(unsafe) private let emptyChunk: UnsafePointer<CChar> = {
    let pointer = UnsafeMutablePointer<CChar>.allocate(capacity: 2)
    pointer.initialize(repeating: 0, count: 2)
    return UnsafePointer(pointer)
}()

/// tree-sitter asks for the text from `byteIndex` on; we answer with the rest of whichever run contains it.
private let readSegments: @convention(c) (UnsafeMutableRawPointer?, UInt32, TSPoint, UnsafeMutablePointer<UInt32>?) -> UnsafePointer<CChar>? = { payload, byteIndex, _, bytesRead in
    guard let payload, let bytesRead else { return nil }
    let segments = payload.assumingMemoryBound(to: Segments.self).pointee
    let index = Int(byteIndex)
    if index < segments.prefixBytes, let prefix = segments.prefix {
        bytesRead.pointee = UInt32(segments.prefixBytes - index)
        return prefix.advanced(by: index).assumingMemoryBound(to: CChar.self)
    }
    let suffixIndex = index - segments.prefixBytes
    if suffixIndex >= 0, suffixIndex < segments.suffixBytes, let suffix = segments.suffix {
        bytesRead.pointee = UInt32(segments.suffixBytes - suffixIndex)
        return suffix.advanced(by: suffixIndex).assumingMemoryBound(to: CChar.self)
    }
    bytesRead.pointee = 0
    return emptyChunk
}

/// Owns a `TSTree`.
final class Tree {
    let pointer: OpaquePointer

    init(_ pointer: OpaquePointer) { self.pointer = pointer }
    deinit { ts_tree_delete(pointer) }

    var rootNode: Node { Node(ts_tree_root_node(pointer)) }

    /// Tells the tree about a change in the text it was parsed from, so the next parse can reuse it.
    func edit(_ edit: TextEdit) {
        var input = TSInputEdit(
            start_byte: UInt32(edit.start * 2),
            old_end_byte: UInt32(edit.oldEnd * 2),
            new_end_byte: UInt32(edit.newEnd * 2),
            start_point: TSPoint(row: UInt32(edit.startPoint.row), column: UInt32(edit.startPoint.column * 2)),
            old_end_point: TSPoint(row: UInt32(edit.oldEndPoint.row), column: UInt32(edit.oldEndPoint.column * 2)),
            new_end_point: TSPoint(row: UInt32(edit.newEndPoint.row), column: UInt32(edit.newEndPoint.column * 2))
        )
        ts_tree_edit(pointer, &input)
    }
}

/// A node in a syntax tree. Byte offsets are UTF-16 bytes, so code-unit offsets are half of them.
struct Node {
    let raw: TSNode

    init(_ raw: TSNode) { self.raw = raw }

    var isNull: Bool { ts_node_is_null(raw) }
    var type: String { String(cString: ts_node_type(raw)) }
    var utf16Range: Range<Int> { Int(ts_node_start_byte(raw) / 2)..<Int(ts_node_end_byte(raw) / 2) }
    var childCount: Int { Int(ts_node_child_count(raw)) }

    func child(at index: Int) -> Node { Node(ts_node_child(raw, UInt32(index))) }

    /// Identity within one tree: same id means same node.
    var id: UnsafeRawPointer? { UnsafeRawPointer(raw.id) }
}
