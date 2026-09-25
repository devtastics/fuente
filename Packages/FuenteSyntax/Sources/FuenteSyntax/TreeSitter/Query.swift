import Foundation
import TreeSitter

enum QueryError: Error, Equatable {
    case syntax(offset: Int)
    case nodeType(offset: Int)
    case field(offset: Int)
    case capture(offset: Int)
    case structure(offset: Int)
    case language
}

/// A compiled tree-sitter query with its per-pattern predicates parsed up front.
final class Query {
    let pointer: OpaquePointer
    let captureNames: [String]

    /// Predicates for each pattern index. Empty when a pattern has none.
    let predicates: [[Predicate]]

    init(language: Language, source: String) throws {
        var errorOffset: UInt32 = 0
        var errorType = TSQueryErrorNone
        let utf8 = Array(source.utf8)
        guard let pointer = utf8.withUnsafeBufferPointer({ buffer in
            buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buffer.count) { chars in
                ts_query_new(language.pointer, chars, UInt32(buffer.count), &errorOffset, &errorType)
            }
        }) else {
            let offset = Int(errorOffset)
            switch errorType {
            case TSQueryErrorNodeType: throw QueryError.nodeType(offset: offset)
            case TSQueryErrorField: throw QueryError.field(offset: offset)
            case TSQueryErrorCapture: throw QueryError.capture(offset: offset)
            case TSQueryErrorStructure: throw QueryError.structure(offset: offset)
            case TSQueryErrorLanguage: throw QueryError.language
            default: throw QueryError.syntax(offset: offset)
            }
        }
        self.pointer = pointer

        captureNames = (0..<ts_query_capture_count(pointer)).map { index in
            var length: UInt32 = 0
            let name = ts_query_capture_name_for_id(pointer, index, &length)!
            return String(decoding: UnsafeRawBufferPointer(start: name, count: Int(length)), as: UTF8.self)
        }

        func stringValue(_ id: UInt32) -> String {
            var length: UInt32 = 0
            let value = ts_query_string_value_for_id(pointer, id, &length)!
            return String(decoding: UnsafeRawBufferPointer(start: value, count: Int(length)), as: UTF8.self)
        }

        predicates = (0..<ts_query_pattern_count(pointer)).map { pattern in
            var stepCount: UInt32 = 0
            guard let steps = ts_query_predicates_for_pattern(pointer, pattern, &stepCount) else { return [] }
            var result: [Predicate] = []
            var arguments: [Predicate.Argument] = []
            for index in 0..<Int(stepCount) {
                let step = steps[index]
                switch step.type {
                case TSQueryPredicateStepTypeCapture:
                    arguments.append(.capture(Int(step.value_id)))
                case TSQueryPredicateStepTypeString:
                    arguments.append(.string(stringValue(step.value_id)))
                default: // Done
                    if let predicate = Predicate(arguments) { result.append(predicate) }
                    arguments.removeAll()
                }
            }
            return result
        }
    }

    deinit { ts_query_delete(pointer) }
}

/// The predicates tree-sitter's own highlighter supports. Anything else passes silently.
enum Predicate {
    enum Argument {
        case capture(Int)
        case string(String)
    }

    case equals(capture: Int, other: Argument, negated: Bool)
    case matches(capture: Int, regex: NSRegularExpression, negated: Bool)
    case anyOf(capture: Int, values: Set<String>, negated: Bool)

    init?(_ arguments: [Argument]) {
        guard case .string(let name)? = arguments.first, arguments.count >= 2, case .capture(let capture) = arguments[1] else { return nil }
        let rest = Array(arguments.dropFirst(2))
        switch name {
        case "eq?", "not-eq?":
            guard let other = rest.first else { return nil }
            self = .equals(capture: capture, other: other, negated: name.hasPrefix("not-"))
        case "match?", "not-match?":
            guard case .string(let pattern)? = rest.first, let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            self = .matches(capture: capture, regex: regex, negated: name.hasPrefix("not-"))
        case "any-of?", "not-any-of?":
            let values = rest.compactMap { if case .string(let value) = $0 { value } else { nil } }
            self = .anyOf(capture: capture, values: Set(values), negated: name.hasPrefix("not-"))
        default:
            return nil
        }
    }

    /// `text(captureIndex)` returns the source text of the match's node for that capture, or `nil` if absent.
    func evaluate(text: (Int) -> String?) -> Bool {
        switch self {
        case .equals(let capture, let other, let negated):
            guard let lhs = text(capture) else { return negated }
            let rhs: String? = switch other {
            case .capture(let index): text(index)
            case .string(let value): value
            }
            return (lhs == rhs) != negated
        case .matches(let capture, let regex, let negated):
            guard let value = text(capture) else { return negated }
            let found = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
            return found != negated
        case .anyOf(let capture, let values, let negated):
            guard let value = text(capture) else { return negated }
            return values.contains(value) != negated
        }
    }
}
