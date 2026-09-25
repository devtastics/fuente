import FuenteText
import Testing
@testable import FuenteSyntax

/// Budgets are generous multiples of an M-series Mac in release, so CI passes and regressions fail.
@Suite(.serialized, .disabled(if: isDebugBuild, "performance budgets only mean something in release"))
struct PerformanceTests {
    /// About 1 MB of realistic PHP: a class repeated with unique names.
    static let bigSource: String = {
        let unit = """
        <?php
        namespace App\\Generated;

        final class Item%d
        {
            public const LIMIT = 10_000;
            private array $rows = [];

            public function __construct(private readonly string $name) {}

            public function load(int $count): int
            {
                for ($i = 0; $i < $count; $i++) {
                    $this->rows[] = sprintf("%%s-%%d", $this->name, $i); // build a row
                }
                return count($this->rows) > self::LIMIT ? self::LIMIT : count($this->rows);
            }
        }

        """
        var parts: [String] = []
        var size = 0
        var index = 0
        while size < 1_000_000 {
            let part = String(format: unit, index)
            parts.append(part)
            size += part.utf8.count
            index += 1
        }
        return parts.joined()
    }()

    @Test func highlightingAMegabyteOfPHP() async {
        let engine = HighlightEngine(language: Languages.php)
        let clock = ContinuousClock()
        var spans: [HighlightSpan] = []
        let elapsed = await clock.measure { spans = await engine.highlights(for: Self.bigSource) }
        print("PERF highlight 1 MB PHP: \(elapsed), spans: \(spans.count), lines: \(Self.bigSource.split(separator: "\n").count)")
        #expect(!spans.isEmpty)
        #expect(elapsed < .seconds(2))

        // What the editor actually does: parse everything, query only a viewport-sized window.
        let units = Array(Self.bigSource.utf16)
        var windowSpans: [HighlightSpan] = []
        let windowed = await clock.measure { windowSpans = await engine.highlights(for: units, in: 500_000..<540_000) }
        print("PERF highlight 1 MB PHP, 40k-unit window: \(windowed), spans: \(windowSpans.count)")
        #expect(!windowSpans.isEmpty)
        #expect(windowSpans.count < spans.count / 10)
        #expect(windowed < .milliseconds(800))

        // A keystroke: one edit, incremental parse, windowed query.
        var storage = TextStorage(Self.bigSource)
        let edit = storage.replace(520_000..<520_000, with: "x")
        var typed: [HighlightSpan] = []
        let incremental = await clock.measure { typed = await engine.highlights(for: storage.utf16Units, in: 500_000..<540_000, edits: [edit]) }
        print("PERF one keystroke in 1 MB PHP (incremental + window): \(incremental), spans: \(typed.count)")
        #expect(!typed.isEmpty)
        #expect(incremental < .milliseconds(100))

        // Scrolling: no edits, same text, another window. No parse at all.
        let scrolled = await clock.measure { typed = await engine.highlights(for: storage.utf16Units, in: 100_000..<140_000) }
        print("PERF scroll to a new window, unchanged text: \(scrolled), spans: \(typed.count)")
        #expect(scrolled < .milliseconds(50))
    }
}

let isDebugBuild: Bool = {
    #if DEBUG
    true
    #else
    false
    #endif
}()
