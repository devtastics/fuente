import AppKit
import FuenteText

/// Keeps a `TextView` highlighted: reparses after every change and colors the visible part of the document.
///
/// Only the lines on screen plus a margin get spans, so memory and query time stay proportional to the
/// viewport, not the file. Scrolling past the covered window triggers another pass.
@MainActor
public final class SyntaxHighlighter {
    public let textView: TextView
    public var theme: Theme {
        didSet { highlight() }
    }

    /// Lines colored above and below the visible ones. Two screens' worth on a typical window.
    public var marginLines = 200

    /// How long after the last pass the syntax tree is kept for incremental parsing. Trees are large
    /// (hundreds of MB for a multi-megabyte file), so they live only while typing is likely to continue.
    public var treeIdleTimeout: Duration = .seconds(4)

    private let engine: HighlightEngine
    private var task: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var coveredRange: Range<Int> = 0..<0

    /// Edits not yet handed to the engine. Every text change appends here; every pass drains it.
    private var pendingEdits: [TextEdit] = []

    public init(textView: TextView, language: Language, theme: Theme) {
        self.textView = textView
        self.theme = theme
        self.engine = HighlightEngine(language: language)
        NotificationCenter.default.addObserver(
            self, selector: #selector(textDidChange), name: TextView.textDidChangeNotification, object: textView
        )
        if let clipView = textView.enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(didScroll), name: NSView.boundsDidChangeNotification, object: clipView
            )
        }
        highlight()
    }

    @objc private func textDidChange(_ notification: Notification) {
        if let edit = notification.userInfo?[TextView.editUserInfoKey] as? TextEdit {
            pendingEdits.append(edit)
        } else {
            // A change we cannot describe: the next pass must parse from scratch.
            pendingEdits.removeAll()
            Task { await engine.reset() }
        }
        highlight()
    }

    /// Scrolling only costs a pass when the viewport leaves the colored window.
    @objc private func didScroll(_ notification: Notification) {
        let visible = textView.visibleCharacterRange()
        if visible.lowerBound < coveredRange.lowerBound || visible.upperBound > coveredRange.upperBound {
            highlight()
        }
    }

    /// Cancels any pending pass and starts one for the current text and viewport. Results land back on the main actor.
    public func highlight() {
        task?.cancel()
        idleTask?.cancel()
        // The storage is a value: the actor shares its buffer copy-on-write and reads it in place.
        let storage = textView.layoutManager.storage
        let range = textView.visibleCharacterRange(marginLines: marginLines)
        let edits = pendingEdits
        pendingEdits.removeAll()
        let engine = engine
        task = Task { [weak self] in
            let start = ContinuousClock.now
            let spans = await engine.highlights(for: storage, in: range, edits: edits)
            guard !Task.isCancelled, let self else { return }
            EditorMetrics.shared.recordHighlight(ContinuousClock.now - start, spans: spans.count)
            self.coveredRange = range
            self.apply(spans)
            self.scheduleTreeRelease()
        }
    }

    /// Drops the engine's tree after `treeIdleTimeout` without another pass. The next edit reparses fully.
    private func scheduleTreeRelease() {
        idleTask?.cancel()
        let timeout = treeIdleTimeout
        let engine = engine
        idleTask = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await engine.reset()
        }
    }

    private func apply(_ spans: [HighlightSpan]) {
        let styles = spans.compactMap { span in
            theme.color(for: span.capture).map { StyledRange(range: span.range, color: $0) }
        }
        textView.setStyles(styles)
    }
}
