import AppKit

/// Draws a document using `TextLayoutManager` and hosts the caret and selection.
/// Designed to be the `documentView` of an `NSScrollView`.
///
/// Coordinates are flipped (y grows downward) so line 0 sits at the top and scrolling matches
/// the layout manager's y offsets directly. Text is not editable yet: this step is navigation.
@MainActor
public final class TextView: NSView {
    public let layoutManager: TextLayoutManager

    /// Posted with the view as object after every text change made through the view.
    public static let textDidChangeNotification = Notification.Name("FuenteText.TextView.textDidChange")

    public var selection = TextSelection(caret: 0) {
        didSet {
            guard selection != oldValue else { return }
            needsDisplay = true
            gutter?.needsDisplay = true
            scrollCaretToVisible()
            restartBlink()
        }
    }

    /// The line-number ruler of the enclosing scroll view, if one is installed.
    var gutter: GutterView? { enclosingScrollView?.verticalRulerView as? GutterView }

    /// Installs a `GutterView` with line numbers in the enclosing scroll view.
    @discardableResult
    public func installGutter() -> GutterView? {
        guard let scrollView = enclosingScrollView else { return nil }
        let gutter = GutterView(scrollView: scrollView, textView: self)
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        return gutter
    }

    /// When true, lines wrap at the visible width. Otherwise the view grows horizontally.
    public var wrapsLines = true {
        didSet { needsLayout = true }
    }

    public var textColor: NSColor = .textColor { didSet { needsDisplay = true } }
    public var backgroundColor: NSColor = .textBackgroundColor { didSet { needsDisplay = true } }

    /// Horizontal inset before the first glyph of every line.
    public var textInset: CGFloat = 8 { didSet { needsLayout = true } }

    /// What the Tab key inserts and what auto-indent adds after an opening bracket.
    public var indentation: Indentation = .spaces(4)

    /// Background of the line holding the caret. `nil` disables it.
    public var currentLineColor: NSColor? = NSColor.textColor.withAlphaComponent(0.05) { didSet { needsDisplay = true } }

    /// Blink state: the caret is drawn only when true. Reset to visible on every selection change.
    private var caretVisible = true
    private var blinkTimer: Timer?
    public var caretBlinkInterval: TimeInterval = 0.55

    public weak var delegate: TextViewDelegate?

    /// Pasteboard used by cut/copy/paste. Injectable for tests.
    public var pasteboard: NSPasteboard = .general

    /// Text being composed by an input method or dead key, shown underlined until committed.
    var composingRange: Range<Int>? { didSet { needsDisplay = true } }

    /// Current run of contiguous typing for undo coalescing. `nil` when the run is broken.
    var typingRun: TypingRun?

    let textUndoManager = UndoManager()

    /// Column to keep while moving vertically, so the caret does not drift on short lines.
    private var verticalMoveX: CGFloat?

    public init(storage: TextStorage, typesetter: LineTypesetter = LineTypesetter()) {
        self.layoutManager = TextLayoutManager(storage: storage, typesetter: typesetter)
        super.init(frame: .zero)
        wantsLayer = true
        textUndoManager.groupsByEvent = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TextView does not support NSCoding") }

    public override var isFlipped: Bool { true }
    public override var isOpaque: Bool { true }
    public override var acceptsFirstResponder: Bool { true }

    public override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        restartBlink()
        return super.becomeFirstResponder()
    }

    public override func resignFirstResponder() -> Bool {
        needsDisplay = true
        stopBlink()
        return super.resignFirstResponder()
    }

    // MARK: - Caret blink

    /// Shows the caret and starts the blink cycle over, so it never blinks away right after moving.
    func restartBlink() {
        stopBlink()
        caretVisible = true
        guard isActive, caretBlinkInterval > 0 else { return }
        blinkTimer = Timer.scheduledTimer(withTimeInterval: caretBlinkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.caretVisible.toggle()
                self.setNeedsDisplay(self.caretRect.insetBy(dx: -1, dy: 0))
            }
        }
    }

    private func stopBlink() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        caretVisible = true
    }

    private var isActive: Bool { window?.firstResponder === self }

    // MARK: - Sizing

    /// Width available for text: the clip view's width when scrolling, otherwise our own.
    private var availableWidth: CGFloat {
        enclosingScrollView?.contentView.bounds.width ?? bounds.width
    }

    private var availableHeight: CGFloat {
        enclosingScrollView?.contentView.bounds.height ?? 0
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

    // MARK: - Styles

    /// Applies highlight colors. Metrics are untouched, so this never scrolls or reflows.
    public func setStyles(_ styles: [StyledRange]) {
        layoutManager.setStyles(styles)
        needsDisplay = true
    }

    /// Dynamic colors resolve at typesetting time, so glyph runs must be rebuilt when the appearance flips.
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layoutManager.invalidateLayoutsKeepingHeights()
        needsDisplay = true
    }

    // MARK: - Geometry

    /// Caret rectangle in view coordinates.
    public var caretRect: CGRect {
        layoutManager.caretRect(at: selection.head).offsetBy(dx: textInset, dy: 0)
    }

    /// Offset under a point in view coordinates.
    public func offset(at point: CGPoint) -> Int {
        layoutManager.offset(at: CGPoint(x: point.x - textInset, y: point.y))
    }

    private func scrollCaretToVisible() {
        guard enclosingScrollView != nil else { return }
        scrollToVisible(caretRect.insetBy(dx: -textInset, dy: 0))
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        backgroundColor.setFill()
        dirtyRect.fill()

        drawCurrentLine()
        drawSelection()

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

        drawMarkedText()
        drawCaret()

        // Typesetting real lines may have changed the document height; resize outside of draw.
        if layoutManager.contentHeight != heightBefore {
            needsLayout = true
        }
    }

    private func drawCurrentLine() {
        guard let currentLineColor, selection.isEmpty, isActive else { return }
        let line = storage.line(at: selection.head)
        let rect = CGRect(x: 0, y: layoutManager.yOffset(ofLine: line), width: bounds.width, height: layoutManager.height(ofLine: line))
        currentLineColor.setFill()
        rect.fill()
    }

    private func drawSelection() {
        guard !selection.isEmpty else { return }
        let color: NSColor = isActive ? .selectedTextBackgroundColor : .unemphasizedSelectedTextBackgroundColor
        color.setFill()
        for rect in layoutManager.selectionRects(for: selection.range) {
            rect.offsetBy(dx: textInset, dy: 0).fill()
        }
    }

    private func drawMarkedText() {
        guard let composingRange else { return }
        textColor.setFill()
        for rect in layoutManager.selectionRects(for: composingRange, newlineWidth: 0) {
            CGRect(x: rect.minX + textInset, y: rect.maxY - 1.5, width: rect.width, height: 1).fill()
        }
    }

    private func drawCaret() {
        guard isActive, selection.isEmpty, caretVisible else { return }
        NSColor.textInsertionPointColor.setFill()
        caretRect.fill()
    }

    // MARK: - Mouse

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        select(at: point, extending: event.modifierFlags.contains(.shift))
    }

    public override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        select(at: point, extending: true)
    }

    /// Places the caret at `point`, or extends the selection to it.
    public func select(at point: CGPoint, extending: Bool) {
        let offset = offset(at: point)
        selection = extending ? TextSelection(anchor: selection.anchor, head: offset) : TextSelection(caret: offset)
        verticalMoveX = nil
        typingRun = nil
    }

    // MARK: - Keyboard

    public override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    public override func insertText(_ insertString: Any) {
        insertText(insertString, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private var storage: TextStorage { layoutManager.storage }

    private func move(to offset: Int, extending: Bool) {
        selection = extending ? TextSelection(anchor: selection.anchor, head: offset) : TextSelection(caret: offset)
        typingRun = nil
    }

    private func moveHorizontally(to offset: Int, extending: Bool) {
        verticalMoveX = nil
        move(to: offset, extending: extending)
    }

    private func moveVertically(by rows: Int, extending: Bool) {
        let caret = layoutManager.caretRect(at: selection.head)
        let x = verticalMoveX ?? caret.minX
        verticalMoveX = x
        let y = rows > 0 ? caret.maxY + caret.height / 2 : caret.minY - caret.height / 2
        let offset: Int
        if y < 0 {
            offset = 0
        } else if y >= layoutManager.contentHeight {
            offset = storage.utf16Count
        } else {
            offset = layoutManager.offset(at: CGPoint(x: x, y: y))
        }
        move(to: offset, extending: extending)
    }

    public override func moveLeft(_ sender: Any?) {
        let target = selection.isEmpty ? storage.offset(before: selection.head) : selection.range.lowerBound
        moveHorizontally(to: target, extending: false)
    }

    public override func moveRight(_ sender: Any?) {
        let target = selection.isEmpty ? storage.offset(after: selection.head) : selection.range.upperBound
        moveHorizontally(to: target, extending: false)
    }

    public override func moveLeftAndModifySelection(_ sender: Any?) {
        moveHorizontally(to: storage.offset(before: selection.head), extending: true)
    }

    public override func moveRightAndModifySelection(_ sender: Any?) {
        moveHorizontally(to: storage.offset(after: selection.head), extending: true)
    }

    public override func moveUp(_ sender: Any?) { moveVertically(by: -1, extending: false) }
    public override func moveDown(_ sender: Any?) { moveVertically(by: 1, extending: false) }
    public override func moveUpAndModifySelection(_ sender: Any?) { moveVertically(by: -1, extending: true) }
    public override func moveDownAndModifySelection(_ sender: Any?) { moveVertically(by: 1, extending: true) }

    private var currentLineRange: Range<Int> { storage.lineRange(storage.line(at: selection.head)) }

    public override func moveToBeginningOfLine(_ sender: Any?) {
        moveHorizontally(to: currentLineRange.lowerBound, extending: false)
    }

    public override func moveToEndOfLine(_ sender: Any?) {
        moveHorizontally(to: currentLineRange.upperBound, extending: false)
    }

    public override func moveToBeginningOfLineAndModifySelection(_ sender: Any?) {
        moveHorizontally(to: currentLineRange.lowerBound, extending: true)
    }

    public override func moveToEndOfLineAndModifySelection(_ sender: Any?) {
        moveHorizontally(to: currentLineRange.upperBound, extending: true)
    }

    public override func moveToBeginningOfDocument(_ sender: Any?) { moveHorizontally(to: 0, extending: false) }
    public override func moveToEndOfDocument(_ sender: Any?) { moveHorizontally(to: storage.utf16Count, extending: false) }

    public override func moveToBeginningOfDocumentAndModifySelection(_ sender: Any?) {
        moveHorizontally(to: 0, extending: true)
    }

    public override func moveToEndOfDocumentAndModifySelection(_ sender: Any?) {
        moveHorizontally(to: storage.utf16Count, extending: true)
    }

    public override func selectAll(_ sender: Any?) {
        selection = TextSelection(anchor: 0, head: storage.utf16Count)
        typingRun = nil
    }
}
