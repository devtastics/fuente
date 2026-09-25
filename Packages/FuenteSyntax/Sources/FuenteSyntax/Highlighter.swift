import Foundation
import os

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
/// Every call is a full parse for now. tree-sitter parses tens of thousands of lines in a few
/// milliseconds, so incremental parsing waits until profiling asks for it.
public actor HighlightEngine {
    public let language: Language
    private lazy var parser = Parser(language: language)
    private lazy var query = try! Query(language: language, source: language.highlightsQuery)

    public init(language: Language) {
        self.language = language
    }

    private static let signposter = OSSignposter(subsystem: "com.devtastics.fuente", category: "syntax")

    /// Spans in document order. Where several patterns capture the same range, the first pattern in
    /// the query wins, matching tree-sitter's own highlighter. Nested spans follow their containers.
    public func highlights(for text: String) -> [HighlightSpan] {
        highlights(for: Array(text.utf16))
    }

    /// Same, from UTF-16 code units: what `TextStorage` holds and what tree-sitter parses natively.
    public func highlights(for units: [UInt16]) -> [HighlightSpan] {
        let parseState = Self.signposter.beginInterval("parse")
        let tree = parser.parse(units)
        Self.signposter.endInterval("parse", parseState)
        guard let tree else { return [] }

        let queryState = Self.signposter.beginInterval("query")
        defer { Self.signposter.endInterval("query", queryState) }
        let cursor = QueryCursor()
        cursor.execute(query, on: tree.rootNode)

        var raw: [(span: HighlightSpan, pattern: Int)] = []
        while let match = cursor.nextMatch() {
            let text: (Int) -> String? = { captureIndex in
                guard let capture = match.captures.first(where: { $0.index == captureIndex }) else { return nil }
                let range = capture.node.utf16Range
                return String(utf16CodeUnits: Array(units[range]), count: range.count)
            }
            guard query.predicates[match.patternIndex].allSatisfy({ $0.evaluate(text: text) }) else { continue }
            for capture in match.captures {
                let range = capture.node.utf16Range
                guard !range.isEmpty else { continue }
                raw.append((HighlightSpan(range: range, capture: query.captureNames[capture.index]), match.patternIndex))
            }
        }

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
