import AppKit
import FuenteText

/// Keeps a `TextView` highlighted: reparses after every change and applies the theme's colors.
@MainActor
public final class SyntaxHighlighter {
    public let textView: TextView
    public var theme: Theme {
        didSet { apply(lastSpans) }
    }

    private let engine: HighlightEngine
    private var task: Task<Void, Never>?
    private var lastSpans: [HighlightSpan] = []

    public init(textView: TextView, language: Language, theme: Theme) {
        self.textView = textView
        self.theme = theme
        self.engine = HighlightEngine(language: language)
        NotificationCenter.default.addObserver(
            self, selector: #selector(textDidChange), name: TextView.textDidChangeNotification, object: textView
        )
        highlight()
    }

    @objc private func textDidChange(_ notification: Notification) {
        highlight()
    }

    /// Cancels any pending pass and starts one for the current text. Results land back on the main actor.
    public func highlight() {
        task?.cancel()
        let units = textView.layoutManager.storage.utf16Units
        let engine = engine
        task = Task { [weak self] in
            let start = ContinuousClock.now
            let spans = await engine.highlights(for: units)
            guard !Task.isCancelled, let self else { return }
            EditorMetrics.shared.recordHighlight(ContinuousClock.now - start, spans: spans.count)
            self.lastSpans = spans
            self.apply(spans)
        }
    }

    private func apply(_ spans: [HighlightSpan]) {
        let styles = spans.compactMap { span in
            theme.color(for: span.capture).map { StyledRange(range: span.range, color: $0) }
        }
        textView.setStyles(styles)
    }
}
