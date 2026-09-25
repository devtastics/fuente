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
