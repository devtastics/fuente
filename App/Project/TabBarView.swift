import AppKit
import FuenteWorkspace

/// Editor tabs: one per open document, in workspace order. Pure display; the window owns the actions.
@MainActor
final class TabBarView: NSView {
    static let height: CGFloat = 30

    var onSelect: ((Document) -> Void)?
    var onClose: ((Document) -> Void)?

    private let stack = NSStackView()
    private let scrollView = NSScrollView()
    private var items: [TabItemView] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        stack.orientation = .horizontal
        stack.spacing = 0
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.documentView = stack
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TabBarView does not support NSCoding") }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: TabBarView.height) }

    /// Rebuilds the tabs. Cheap enough for a handful of documents; diffing can come later.
    func reload(documents: [Document], active: Document?) {
        items.forEach { stack.removeView($0) }
        items = documents.map { document in
            let item = TabItemView(document: document)
            item.isActive = document === active
            item.onSelect = { [weak self] in self?.onSelect?(document) }
            item.onClose = { [weak self] in self?.onClose?(document) }
            stack.addView(item, in: .leading)
            return item
        }
        if let index = documents.firstIndex(where: { $0 === active }) {
            items[index].scrollToVisible(items[index].bounds)
        }
    }

    /// Refreshes titles and dirty dots without rebuilding.
    func refresh() {
        items.forEach { $0.update() }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    override var isFlipped: Bool { true }
}

/// One tab. Shows the document name, a dot when dirty, and a close button on hover.
@MainActor
final class TabItemView: NSView {
    let document: Document
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    var isActive = false {
        didSet { needsDisplay = true; update() }
    }

    private let label = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var isHovered = false { didSet { update() } }
    private var trackingArea: NSTrackingArea?

    init(document: Document) {
        self.document = document
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setButtonType(.momentaryChange)

        addSubview(label)
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            widthAnchor.constraint(lessThanOrEqualToConstant: 220),
            heightAnchor.constraint(equalToConstant: TabBarView.height),
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -30),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TabItemView does not support NSCoding") }

    func update() {
        label.stringValue = document.name
        label.textColor = isActive ? .labelColor : .secondaryLabelColor
        let showsClose = isHovered || isActive
        let symbol = document.isDirty && !isHovered ? "circle.fill" : "xmark"
        let config = NSImage.SymbolConfiguration(pointSize: document.isDirty && !isHovered ? 7 : 9, weight: .semibold)
        closeButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Close")?.withSymbolConfiguration(config)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.isHidden = !(showsClose || document.isDirty)
        toolTip = document.url?.path
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { onClose?() }
    }

    @objc private func closeTapped() {
        onClose?()
    }

    override func draw(_ dirtyRect: NSRect) {
        if isActive {
            NSColor.textBackgroundColor.setFill()
            bounds.fill()
        }
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: 6, width: 1, height: bounds.height - 12).fill()
    }
}
