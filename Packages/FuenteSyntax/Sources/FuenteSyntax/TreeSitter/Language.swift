import TreeSitter

/// A tree-sitter grammar plus the highlight query that goes with it.
///
/// The language pointer is immutable static data from the grammar, safe to share across threads.
public struct Language: @unchecked Sendable {
    public let name: String
    public let fileExtensions: [String]
    public let highlightsQuery: String
    let pointer: OpaquePointer

    public init(name: String, fileExtensions: [String], pointer: OpaquePointer, highlightsQuery: String) {
        self.name = name
        self.fileExtensions = fileExtensions
        self.pointer = pointer
        self.highlightsQuery = highlightsQuery
    }
}
