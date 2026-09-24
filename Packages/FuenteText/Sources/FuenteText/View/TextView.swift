import AppKit

/// Draws a document using `TextLayoutManager`. Designed to be the `documentView` of an `NSScrollView`.
///
/// Read-only for now: this step is layout and rendering. Coordinates are flipped (y grows downward)
/// so line 0 sits at the top and scrolling matches the layout manager's y offsets directly.
@MainActor
public final class TextView: NSView {
    public let layoutManager: TextLayoutManager

    /// When true, lines wrap at the visible width. Otherwise the view grows horizontally.
    public var wrapsLines = true {
        didSet { needsLayout = true }
    }

    public var textColor: NSColor = .textColor { didSet { needsDisplay = true } }
    public var backgroundColor: NSColor = .textBackgroundColor { didSet { needsDisplay = true } }

    /// Horizontal inset before the first glyph of every line.
    public var textInset: CGFloat = 8 { didSet { needsLayout = true } }

    public init(storage: TextStorage, typesetter: LineTypesetter = LineTypesetter()) {
        self.layoutManager = TextLayoutManager(storage: storage, typesetter: typesetter)
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TextView does not support NSCoding") }

    public override var isFlipped: Bool { true }
    public override var isOpaque: Bool { true }

    // MARK: - Sizing

    /// Width available for text: the clip view's width when scrolling, otherwise our own.
    private var availableWidth: CGFloat {
        (enclosingScrollView?.contentView.bounds.width ?? bounds.width)
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let clipView = enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(clipViewBoundsChanged),
                name: NSView.boundsDidChangeNotification, object: clipView
            )
        }
        needsLayout = true
    }

    @objc private func clipViewBoundsChanged() {
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        layoutManager.wrapWidth = wrapsLines ? max(0, availableWidth - textInset * 2) : nil
        updateFrameSize()
    }

    /// Grows the view to the document's current size so the scroll view knows how far to scroll.
    private func updateFrameSize() {
        let width = wrapsLines ? availableWidth : max(availableWidth, layoutManager.contentWidth + textInset * 2)
        let height = max(availableHeight, layoutManager.contentHeight)
        let size = CGSize(width: width, height: height)
        if size != frame.size {
            setFrameSize(size)
            needsDisplay = true
        }
    }

    private var availableHeight: CGFloat {
        enclosingScrollView?.contentView.bounds.height ?? 0
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        backgroundColor.setFill()
        dirtyRect.fill()

        // CoreText draws with y up; flip the text matrix once so glyphs come out upright in our flipped view.
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.setFillColor(textColor.cgColor)

        let heightBefore = layoutManager.contentHeight
        for line in layoutManager.layoutLines(in: dirtyRect) {
            var y = line.y
            for fragment in line.fragments {
                context.textPosition = CGPoint(x: textInset, y: y + fragment.ascent)
                CTLineDraw(fragment.ctLine, context)
                y += fragment.height
            }
        }
        context.restoreGState()

        // Typesetting real lines may have changed the document height; resize outside of draw.
        if layoutManager.contentHeight != heightBefore {
            needsLayout = true
        }
    }
}
