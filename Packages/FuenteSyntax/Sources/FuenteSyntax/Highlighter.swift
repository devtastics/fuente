import Foundation
import FuenteText
import os
import TreeSitter

/// A capture name over a UTF-16 range of the document, e.g. `keyword` over `function`.
public struct HighlightSpan: Sendable, Equatable {
    public let range: Range<Int>
    public let capture: String

    public init(range: Range<Int>, capture: String) {
        self.range = range
        self.capture = capture
    }
}

/// Parses and highlights documents for one language, off the main thread.
///
/// Keeps the last syntax tree. Callers describe changes as `TextEdit`s so the next parse reuses everything
/// the edit did not touch, and a call without edits and with the same length skips parsing altogether.
public actor HighlightEngine {
    public let language: Language
    private lazy var parser = Parser(language: language)
    private lazy var query = try! Query(language: language, source: language.highlightsQuery)

    /// Tree of the last text parsed, and that text's length as a cheap consistency check.
    var tree: Tree?  // internal for tests
    private var parsedCount = -1

    public init(language: Language) {
        self.language = language
    }

    /// S-expression and node ranges of the current tree. For tests.
    func debugTree() -> (sexp: String, ranges: [String]) {
        guard let tree else { return ("", []) }
        var out: [String] = []
        func walk(_ node: Node) {
            out.append("\(node.type) \(node.utf16Range)")
            for index in 0..<node.childCount { walk(node.child(at: index)) }
        }
        walk(tree.rootNode)
        return (String(cString: ts_node_string(tree.rootNode.raw)), out)
    }

    /// Forgets the previous tree. The next call parses from scratch. A tree costs roughly 60 bytes per
    /// byte of dense source, so owners release it once typing stops.
    public func reset() {
        tree = nil
        parsedCount = -1
    }

    private static let signposter = OSSignposter(subsystem: "com.devtastics.fuente", category: "syntax")

    /// Spans in document order. Where several patterns capture the same range, the first pattern in
    /// the query wins, matching tree-sitter's own highlighter. Nested spans follow their containers.
    public func highlights(for text: String) -> [HighlightSpan] {
        highlights(for: TextStorage(text))
    }

    /// Same, from UTF-16 code units.
    public func highlights(for units: [UInt16], in range: Range<Int>? = nil, edits: [TextEdit] = []) -> [HighlightSpan] {
        highlights(for: TextStorage(utf16Units: units), in: range, edits: edits)
    }

    /// The main entry point: reads the storage in place, no copy. With `range`, only captures intersecting
    /// it are returned. `edits` are the changes since the previous call, in order; with them the parse is
    /// incremental, without them and with an unchanged length the previous tree is reused as is.
    ///
    /// With `parseWindow`, only that part of the document (plus its first line, so grammars like PHP see
    /// their opening tag) is parsed, from scratch, and nothing is retained: memory and time then depend on
    /// the window, not the file. `range` should lie inside the window.
    public func highlights(for storage: TextStorage, in range: Range<Int>? = nil, edits: [TextEdit] = [], parseWindow: Range<Int>? = nil) -> [HighlightSpan] {
        let parseState = Self.signposter.beginInterval("parse")
        let tree = parseWindow.map { parseWindowed(storage, window: $0) } ?? parse(storage, edits: edits)
        Self.signposter.endInterval("parse", parseState)
        guard let tree else { return [] }

        let queryState = Self.signposter.beginInterval("query")
        defer { Self.signposter.endInterval("query", queryState) }
        let cursor = QueryCursor()
        cursor.execute(query, on: tree.rootNode, utf16Range: range)

        var raw: [(span: HighlightSpan, pattern: Int)] = []
        while let match = cursor.nextMatch() {
            let text: (Int) -> String? = { captureIndex in
                guard let capture = match.captures.first(where: { $0.index == captureIndex }) else { return nil }
                return storage.substring(capture.node.utf16Range)
            }
            guard query.predicates[match.patternIndex].allSatisfy({ $0.evaluate(text: text) }) else { continue }
            for capture in match.captures {
                let range = capture.node.utf16Range
                guard !range.isEmpty else { continue }
                raw.append((HighlightSpan(range: range, capture: query.captureNames[capture.index]), match.patternIndex))
            }
        }

        return resolve(raw)
    }

    /// Parses the first line plus `window`, returns the tree and keeps none of it.
    private func parseWindowed(_ storage: TextStorage, window: Range<Int>) -> Tree? {
        reset()
        let firstLineEnd = min(storage.utf16Count, storage.lineCount > 1 ? storage.lineStarts[1] : storage.utf16Count)
        let window = window.clamped(to: 0..<storage.utf16Count)
        let ranges = window.lowerBound <= firstLineEnd ? [0..<max(window.upperBound, firstLineEnd)] : [0..<firstLineEnd, window]
        parser.setIncludedRanges(ranges, in: storage)
        defer { parser.setIncludedRanges(nil, in: storage) }
        return parser.parse(storage)
    }

    private func parse(_ storage: TextStorage, edits: [TextEdit]) -> Tree? {
        if let old = tree {
            if edits.isEmpty, parsedCount == storage.utf16Count {
                return old
            }
            if !edits.isEmpty {
                edits.forEach(old.edit)
                tree = parser.parse(storage, oldTree: old)
                parsedCount = storage.utf16Count
                return tree
            }
        }
        tree = parser.parse(storage)
        parsedCount = storage.utf16Count
        return tree
    }

    /// Orders spans and resolves overlaps. Where several patterns capture the same range, the first pattern
    /// in the query wins, matching tree-sitter's own highlighter.
    private func resolve(_ input: [(span: HighlightSpan, pattern: Int)]) -> [HighlightSpan] {
        var raw = input
        raw.sort { lhs, rhs in
            if lhs.span.range.lowerBound != rhs.span.range.lowerBound { return lhs.span.range.lowerBound < rhs.span.range.lowerBound }
            if lhs.span.range.upperBound != rhs.span.range.upperBound { return lhs.span.range.upperBound > rhs.span.range.upperBound }
            return lhs.pattern < rhs.pattern
        }
        var result: [HighlightSpan] = []
        for entry in raw where result.last?.range != entry.span.range {
            result.append(entry.span)
        }
        return result
    }
}

extension HighlightSpan: Hashable {}
