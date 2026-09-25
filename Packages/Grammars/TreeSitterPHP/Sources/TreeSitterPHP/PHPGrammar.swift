import Foundation
import TreeSitterPHPParser

/// Vendored tree-sitter-php grammar. Update with `update.sh`; do not edit the C sources.
public enum PHPGrammar {
    /// Upstream tag the vendored sources were taken from.
    public static let upstreamVersion = "v0.24.2"

    /// Raw `TSLanguage *` for the PHP grammar.
    public static var language: OpaquePointer { tree_sitter_php()! }

    /// Highlight query shipped with the grammar.
    public static var highlightsQuery: String {
        let url = Bundle.module.url(forResource: "highlights", withExtension: "scm", subdirectory: "queries")!
        return try! String(contentsOf: url, encoding: .utf8)
    }
}
