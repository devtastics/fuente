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
