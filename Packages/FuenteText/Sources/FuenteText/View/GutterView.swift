import AppKit

/// Line numbers beside a `TextView`, as the vertical ruler of its scroll view so AppKit keeps it in sync.
///
/// Numbers sit on the same baseline as the first row of each line. The current line is emphasized.
/// This column is where diagnostics and source control markers will live later.
@MainActor
public final class GutterView: NSRulerView {
    public weak var textView: TextView? {
        didSet { updateThickness() }
    }

    public var textColor: NSColor = .secondaryLabelColor { didSet { needsDisplay = true } }
    public var currentLineColor: NSColor = .labelColor { didSet { needsDisplay = true } }
    public var backgroundColor: NSColor = .textBackgroundColor { didSet { needsDisplay = true } }

    /// Space on each side of the widest number.
    public var padding: CGFloat = 8 { didSet { updateThickness() } }

    public init(scrollView: NSScrollView, textView: TextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        updateThickness()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("GutterView does not support NSCoding") }

    public override var isFlipped: Bool { true }

    private var font: NSFont { textView?.layoutManager.typesetter.font ?? .monospacedSystemFont(ofSize: 12, weight: .regular) }

    private var digitCount: Int { max(2, String(textView?.layoutManager.lineCount ?? 1).count) }

    /// Width of the widest possible number at the current digit count, plus padding.
    public override var requiredThickness: CGFloat {
        let widest = NSAttributedString(string: String(repeating: "8", count: digitCount), attributes: [.font: font])
        return ceil(widest.size().width) + padding * 2
    }

    /// Call when the line count or font may have changed; cheap when nothing did.
    public func updateThickness() {
        let thickness = requiredThickness
        if ruleThickness != thickness { ruleThickness = thickness }
        needsDisplay = true
    }

    public override func drawHashMarksAndLabels(in rect: NSRect) {
        // Everything is drawn in draw(_:); rulers call this from their own draw with their own state.
    }

    public override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        dirtyRect.fill()
        guard let textView else { return }

        let textRect = convert(dirtyRect, to: textView)
        let currentLine = textView.layoutManager.storage.line(at: textView.selection.head)
        let width = ruleThickness - padding

        for line in textView.layoutManager.layoutLines(in: textRect) {
            guard let first = line.fragments.first else { continue }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: line.index == currentLine ? currentLineColor : textColor,
            ]
            let label = NSAttributedString(string: String(line.index + 1), attributes: attributes)
            let size = label.size()
            let baseline = convert(CGPoint(x: 0, y: line.y + first.ascent), from: textView).y
            // NSAttributedString draws from the top of its bounding box; place it so baselines match.
            let top = baseline - (size.height - abs(font.descender))
            label.draw(at: CGPoint(x: width - size.width, y: top))
        }
    }
}
