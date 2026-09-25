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

    /// Above this many bytes of source, only a window around the viewport is parsed (`parseMarginLines`
    /// each side) and no tree is kept: at ~50 bytes of tree per byte of source, a full parse of a 5 MB
    /// file would hold 250 MB. Below it, the whole file is parsed and the tree kept briefly for
    /// incremental reparsing.
    public var windowedParsingThresholdBytes = 200_000

    /// Lines parsed above and below the visible ones in windowed mode. Far enough that a construct cut
    /// at the window's top edge, such as a long comment, resynchronizes before anything visible.
    public var parseMarginLines = 2_000

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
        EditorMetrics.trace("highlight trigger: text change")
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
            EditorMetrics.trace("highlight trigger: scroll visible=\(visible) covered=\(coveredRange)")
            highlight()
        }
    }

    /// Cancels any pending pass and starts one for the current text and viewport. Results land back on the main actor.
    public func highlight() {
        EditorMetrics.trace("highlight pass scheduled")
        task?.cancel()
        idleTask?.cancel()
        // The storage is a value: the actor shares its buffer copy-on-write and reads it in place.
        let storage = textView.layoutManager.storage
        let range = textView.visibleCharacterRange(marginLines: marginLines)
        let windowed = storage.utf16Count * 2 > windowedParsingThresholdBytes
        let parseWindow = windowed ? textView.visibleCharacterRange(marginLines: parseMarginLines) : nil
        let edits = pendingEdits
        pendingEdits.removeAll()
        let engine = engine
        task = Task { [weak self] in
            let start = ContinuousClock.now
            let spans = await engine.highlights(for: storage, in: range, edits: edits, parseWindow: parseWindow)
            guard !Task.isCancelled, let self else { return }
            EditorMetrics.shared.recordHighlight(ContinuousClock.now - start, spans: spans.count)
            self.coveredRange = range
            self.apply(spans)
            if !windowed { self.scheduleTreeRelease() }
        }
    }

    /// Drops the engine's tree after `treeIdleTimeout` without another pass. The next edit then reparses fully.
    private func scheduleTreeRelease() {
        idleTask?.cancel()
        let engine = engine
        let timeout = treeIdleTimeout
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
