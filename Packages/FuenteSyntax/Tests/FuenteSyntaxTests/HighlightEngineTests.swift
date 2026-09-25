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

    @Test func emptyDocumentHasNoSpans() async {
        #expect(await spans("").isEmpty)
    }
}
