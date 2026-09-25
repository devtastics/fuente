import AppKit

/// Find and replace through AppKit's own find bar (`NSTextFinder`): Cmd+F, Cmd+G, Cmd+E, replace, incremental
/// matching with the dimming overlay. The view only describes its text and geometry.
extension TextView: @preconcurrency NSTextFinderClient {
    /// Installs the finder in the enclosing scroll view. Called once the view has a scroll view.
    func installTextFinder() {
        guard let scrollView = enclosingScrollView, textFinder.client == nil else { return }
        textFinder.client = self
        textFinder.findBarContainer = scrollView
        textFinder.isIncrementalSearchingEnabled = true
        textFinder.incrementalSearchingShouldDimContentView = true
        scrollView.findBarPosition = .aboveContent
    }

    public override func performTextFinderAction(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag ?? (sender as? NSControl)?.tag,
              let action = NSTextFinder.Action(rawValue: tag) else { return }
        textFinder.performAction(action)
    }

    // MARK: - NSTextFinderClient

    public var string: String { layoutManager.storage.string }

    public var isSelectable: Bool { true }
    public var allowsMultipleSelection: Bool { false }
    public var isEditable: Bool { true }

    public var firstSelectedRange: NSRange { NSRange(selection.range) }

    public var selectedRanges: [NSValue] {
        get { [NSValue(range: NSRange(selection.range))] }
        set {
            guard let range = newValue.first.flatMap({ Range($0.rangeValue) }) else { return }
            selection = TextSelection(anchor: range.lowerBound, head: range.upperBound)
        }
    }

    public func scrollRangeToVisible(_ range: NSRange) {
        guard let range = Range(range) else { return }
        let rects = layoutManager.selectionRects(for: range.isEmpty ? range.lowerBound..<(range.lowerBound + 1) : range)
        let union = rects.dropFirst().reduce(rects.first ?? layoutManager.caretRect(at: range.lowerBound)) { $0.union($1) }
        scrollToVisible(union.offsetBy(dx: textInset, dy: 0).insetBy(dx: -textInset, dy: -8))
    }

    public func rects(forCharacterRange range: NSRange) -> [NSValue]? {
        guard let range = Range(range) else { return nil }
        return layoutManager.selectionRects(for: range, newlineWidth: 0).map { NSValue(rect: $0.offsetBy(dx: textInset, dy: 0)) }
    }

    public var visibleCharacterRanges: [NSValue] {
        let visible = visibleRect
        let storage = layoutManager.storage
        let first = layoutManager.line(atY: max(0, visible.minY))
        let last = layoutManager.line(atY: max(0, visible.maxY - 1))
        let range = storage.lineStarts[first]..<storage.lineRange(last).upperBound
        return [NSValue(range: NSRange(range))]
    }

    /// Draws just the matched characters into the finder's overlay, on top of the dimmed content.
    public func drawCharacters(in range: NSRange, forContentView view: NSView) {
        guard let range = Range(range), let context = NSGraphicsContext.current?.cgContext else { return }
        let rects = layoutManager.selectionRects(for: range, newlineWidth: 0).map { $0.offsetBy(dx: textInset, dy: 0) }
        guard !rects.isEmpty else { return }
        context.saveGState()
        context.clip(to: rects)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.setFillColor(textColor.cgColor)
        let storage = layoutManager.storage
        for line in storage.line(at: range.lowerBound)...storage.line(at: range.upperBound) {
            var y = layoutManager.yOffset(ofLine: line)
            for fragment in layoutManager.ensureLayout(line) {
                context.textPosition = CGPoint(x: textInset, y: y + fragment.ascent)
                CTLineDraw(fragment.ctLine, context)
                y += fragment.height
            }
        }
        context.restoreGState()
    }

    public func contentView(at index: Int, effectiveCharacterRange outRange: NSRangePointer) -> NSView {
        outRange.pointee = NSRange(location: 0, length: layoutManager.storage.utf16Count)
        return self
    }

    public func replaceCharacters(in range: NSRange, with string: String) {
        guard let range = Range(range) else { return }
        typingRun = nil
        replace(range, with: string)
    }

    public func shouldReplaceCharacters(inRanges ranges: [NSValue], with strings: [String]) -> Bool { true }

    public func didReplaceCharacters() {}
}

extension TextView: NSUserInterfaceValidations {
    /// Enables or disables the Find menu items according to the finder's state.
    public func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(performTextFinderAction(_:)), let action = NSTextFinder.Action(rawValue: item.tag) {
            return textFinder.validateAction(action)
        }
        return true
    }
}
