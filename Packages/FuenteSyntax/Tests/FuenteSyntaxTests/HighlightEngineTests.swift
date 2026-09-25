import FuenteText
import Testing
@testable import FuenteSyntax

@Suite struct HighlightEngineTests {
    let engine = HighlightEngine(language: Languages.php)

    private func spans(_ source: String) async -> [HighlightSpan] {
        await engine.highlights(for: source)
    }

    /// The span whose capture starts with `capture` and whose text is exactly `text`.
    private func span(_ spans: [HighlightSpan], _ capture: String, text: String, in source: String) -> HighlightSpan? {
        let units = Array(source.utf16)
        return spans.first { span in
            span.capture.split(separator: ".").first.map(String.init) == capture
                && String(utf16CodeUnits: Array(units[span.range]), count: span.range.count) == text
        }
    }

    @Test func parsesAProgram() {
        let parser = Parser(language: Languages.php)
        let tree = parser.parse(Array("<?php echo 1;".utf16))!
        #expect(tree.rootNode.type == "program")
        #expect(tree.rootNode.utf16Range == 0..<13)
        #expect(tree.rootNode.childCount > 0)
    }

    @Test func queryCompilesWithPredicates() throws {
        let query = try Query(language: Languages.php, source: Languages.php.highlightsQuery)
        #expect(query.captureNames.contains("keyword"))
        #expect(query.predicates.contains { !$0.isEmpty })
    }

    @Test func highlightsTheBasics() async {
        let source = "<?php\nfunction foo($bar) {\n    return \"hi\"; // note\n}"
        let result = await spans(source)
        #expect(span(result, "tag", text: "<?php", in: source) != nil)
        #expect(span(result, "keyword", text: "function", in: source) != nil)
        #expect(span(result, "keyword", text: "return", in: source) != nil)
        #expect(span(result, "function", text: "foo", in: source) != nil)
        #expect(span(result, "variable", text: "$bar", in: source) != nil)
        #expect(span(result, "string", text: "\"hi\"", in: source) != nil)
        #expect(span(result, "comment", text: "// note", in: source) != nil)
    }

    @Test func predicatesDecideCaptures() async {
        let source = "<?php $x = FOO_BAR; $y = $this->name; $z = new Foo(); class A { public function __construct() {} }"
        let result = await spans(source)
        #expect(span(result, "constant", text: "FOO_BAR", in: source) != nil)      // #match? uppercase
        #expect(span(result, "variable", text: "this", in: source)?.capture == "variable.builtin") // #eq? "this"
        #expect(span(result, "constructor", text: "__construct", in: source) != nil) // #eq? "__construct"
        #expect(span(result, "constant", text: "name", in: source) == nil)          // lowercase: not a constant
    }

    @Test func spansAreOrderedAndDeduplicated() async {
        let source = "<?php\n$a = 1;\n$b = 2;"
        let result = await spans(source)
        for (previous, next) in zip(result, result.dropFirst()) {
            #expect(previous.range.lowerBound <= next.range.lowerBound)
            #expect(previous.range != next.range)
        }
    }

    @Test func rangeLimitsSpansToTheWindow() async {
        let source = "<?php\n$a = 1;\n$b = 2;\n$c = 3;"
        let all = await engine.highlights(for: Array(source.utf16))
        let window = await engine.highlights(for: Array(source.utf16), in: 14..<21) // "$b = 2;"
        #expect(window.count < all.count)
        #expect(window.allSatisfy { $0.range.upperBound > 14 && $0.range.lowerBound < 21 })
        #expect(span(window, "variable", text: "$b", in: source) != nil)
        #expect(span(window, "variable", text: "$a", in: source) == nil)
    }

    /// Incremental results must equal a fresh parse after any sequence of edits that leaves the code valid.
    /// (With syntax errors tree-sitter's recovery depends on history, so trees may legitimately differ.)
    @Test func incrementalMatchesFullParse() async {
        let incremental = HighlightEngine(language: Languages.php)
        var storage = TextStorage("<?php\nfunction foo($bar) {\n    return $bar + 1;\n}\n")
        _ = await incremental.highlights(for: storage.utf16Units)

        /// Replaces the first occurrence of `needle`, returning the edit.
        func replaceFirst(_ needle: String, with text: String) -> TextEdit {
            let units = storage.utf16Units
            let target = Array(needle.utf16)
            let start = (0...(units.count - target.count)).first { Array(units[$0..<($0 + target.count)]) == target }!
            return storage.replace(start..<(start + target.count), with: text)
        }

        let steps: [() -> TextEdit] = [
            { replaceFirst("<?php\n", with: "<?php\n// comment\n") },                 // insert a line
            { replaceFirst("$bar + 1", with: "$bar + 42") },                           // change a literal
            { replaceFirst("foo(", with: "foo(int $extra, ") },                        // add a parameter
            { replaceFirst("<?php\n", with: "<?php declare(strict_types=1);\n") },     // replace the opening
            { replaceFirst("// comment\n", with: "") },                                // delete a line
            { storage.replace(storage.utf16Count..<storage.utf16Count, with: "\n$x = \"tail\";") }, // append
        ]
        for (index, step) in steps.enumerated() {
            let edit = step()
            let result = await incremental.highlights(for: storage.utf16Units, edits: [edit])
            let expected = await HighlightEngine(language: Languages.php).highlights(for: storage.utf16Units)
            #expect(result == expected, "step \(index): \(storage.string.debugDescription)")
        }
    }

    /// Breaking the code and repairing it must converge on the fresh parse once the code is valid again.
    @Test func recoversAfterBrokenIntermediateStates() async {
        let incremental = HighlightEngine(language: Languages.php)
        var storage = TextStorage("<?php\nfunction foo($bar) {\n    return $bar;\n}\n")
        _ = await incremental.highlights(for: storage.utf16Units)
        let brace = storage.utf16Units.firstIndex(of: UInt16(ascii: "{"))!
        let broken = storage.replace(brace..<(brace + 1), with: "")   // remove "{"
        _ = await incremental.highlights(for: storage.utf16Units, edits: [broken])
        let fixed = storage.replace(brace..<brace, with: "{")         // put it back
        let result = await incremental.highlights(for: storage.utf16Units, edits: [fixed])
        let expected = await HighlightEngine(language: Languages.php).highlights(for: storage.utf16Units)
        #expect(result == expected)
        #expect(span(result, "function", text: "foo", in: storage.string) != nil)
    }

    @Test func batchedEditsAreAppliedInOrder() async {
        let engine = HighlightEngine(language: Languages.php)
        let fresh = HighlightEngine(language: Languages.php)
        var storage = TextStorage("<?php $a = 1;")
        _ = await engine.highlights(for: storage.utf16Units)
        let first = storage.replace(6..<6, with: "$b = 2; ")
        let second = storage.replace(storage.utf16Count..<storage.utf16Count, with: " $c = 3;")
        let spans = await engine.highlights(for: storage.utf16Units, edits: [first, second])
        #expect(spans == (await fresh.highlights(for: storage.utf16Units)))
    }

    @Test func unchangedTextReusesTheTree() async {
        let engine = HighlightEngine(language: Languages.php)
        let units = Array("<?php $a = 1;\n$b = 2;".utf16)
        let first = await engine.highlights(for: units, in: 0..<13)
        let second = await engine.highlights(for: units, in: 13..<21)
        #expect(!first.isEmpty && !second.isEmpty)
        #expect(first != second)
        #expect((first + second).count == (await engine.highlights(for: units)).count)
    }

    @Test func emptyDocumentHasNoSpans() async {
        #expect(await spans("").isEmpty)
    }
}
