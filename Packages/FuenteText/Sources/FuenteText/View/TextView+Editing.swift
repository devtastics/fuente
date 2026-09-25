import AppKit

/// Notified when the text changes through the view.
@MainActor
public protocol TextViewDelegate: AnyObject {
    func textViewDidChangeText(_ textView: TextView)
}

/// A run of contiguous typing, undone as one action. Extended in place while typing continues.
final class TypingRun {
    var range: Range<Int>
    let replacedText: String

    init(range: Range<Int>, replacedText: String) {
        self.range = range
        self.replacedText = replacedText
    }
}

extension TextView {
    // MARK: - Central edit

    /// Every text mutation goes through here: it edits, registers undo, moves the caret and redraws.
    func replace(_ range: Range<Int>, with text: String, selectionAfter: TextSelection? = nil, registerUndo: Bool = true) {
        let replaced = String(layoutManager.storage.substring(range))
        let newRange = range.lowerBound..<(range.lowerBound + text.utf16.count)
        textFinder.noteClientStringWillChange()

        if registerUndo {
            let selectionBefore = selection
            registerUndoAction { view in
                view.replace(newRange, with: replaced, selectionAfter: selectionBefore)
            }
        }

        let start = ContinuousClock.now
        let edit = layoutManager.replace(range, with: text)
        EditorMetrics.shared.recordEdit(ContinuousClock.now - start)
        selection = selectionAfter ?? TextSelection(caret: newRange.upperBound)
        didEdit(edit)
    }

    /// One undo group per registration, independent of the run loop, so each undo reverts exactly one edit
    /// (or one typing run). While undoing or redoing, the manager routes registrations itself.
    private func registerUndoAction(_ action: @escaping @MainActor (TextView) -> Void) {
        let manager = textUndoManager
        let grouped = !manager.isUndoing && !manager.isRedoing
        if grouped { manager.beginUndoGrouping() }
        manager.registerUndo(withTarget: self) { view in
            MainActor.assumeIsolated { action(view) }
        }
        if grouped { manager.endUndoGrouping() }
    }

    func didEdit(_ edit: TextEdit) {
        needsLayout = true
        needsDisplay = true
        gutter?.updateThickness()
        delegate?.textViewDidChangeText(self)
        NotificationCenter.default.post(
            name: TextView.textDidChangeNotification, object: self, userInfo: [TextView.editUserInfoKey: edit]
        )
    }

    /// Inserts typed text, coalescing consecutive keystrokes into one undo action.
    func insertTyped(_ text: String) {
        let range = selection.range
        if let run = typingRun, range.isEmpty, range.lowerBound == run.range.upperBound {
            // Extend the current run: undo of the run will remove everything it now covers.
            replace(range, with: text, registerUndo: false)
            run.range = run.range.lowerBound..<(run.range.upperBound + text.utf16.count)
        } else {
            let run = TypingRun(range: range.lowerBound..<(range.lowerBound + text.utf16.count),
                                replacedText: String(layoutManager.storage.substring(range)))
            let selectionBefore = selection
            replace(range, with: text, registerUndo: false)
            registerUndoAction { view in
                view.replace(run.range, with: run.replacedText, selectionAfter: selectionBefore)
            }
            typingRun = run
        }
    }

    // MARK: - Deletion

    public override func deleteBackward(_ sender: Any?) {
        typingRun = nil
        let range = selection.isEmpty
            ? layoutManager.storage.offset(before: selection.head)..<selection.head
            : selection.range
        guard !range.isEmpty else { return }
        replace(range, with: "")
    }

    public override func deleteForward(_ sender: Any?) {
        typingRun = nil
        let range = selection.isEmpty
            ? selection.head..<layoutManager.storage.offset(after: selection.head)
            : selection.range
        guard !range.isEmpty else { return }
        replace(range, with: "")
    }

    /// Newline keeps the current line's indentation and adds one level after an opening bracket.
    public override func insertNewline(_ sender: Any?) {
        typingRun = nil
        let storage = layoutManager.storage
        let range = selection.range
        let lineRange = storage.lineRange(storage.line(at: range.lowerBound))
        let lineText = storage.substring(lineRange.lowerBound..<range.lowerBound)
        let leading = String(lineText.prefix { $0 == " " || $0 == "\t" })
        let opensBlock = lineText.last.map { "{([".contains($0) } ?? false
        replace(range, with: "\n" + leading + (opensBlock ? indentation.unit : ""))
    }

    public override func insertTab(_ sender: Any?) {
        insertTyped(indentation.unit)
    }

    // MARK: - Undo

    public override var undoManager: UndoManager? { textUndoManager }

    @objc public func undo(_ sender: Any?) {
        typingRun = nil
        textUndoManager.undo()
    }

    @objc public func redo(_ sender: Any?) {
        typingRun = nil
        textUndoManager.redo()
    }

    // MARK: - Pasteboard

    @objc public func copy(_ sender: Any?) {
        guard !selection.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(String(layoutManager.storage.substring(selection.range)), forType: .string)
    }

    @objc public func cut(_ sender: Any?) {
        guard !selection.isEmpty else { return }
        copy(sender)
        typingRun = nil
        replace(selection.range, with: "")
    }

    @objc public func paste(_ sender: Any?) {
        guard let text = pasteboard.string(forType: .string) else { return }
        typingRun = nil
        replace(selection.range, with: text)
    }
}

// MARK: - NSTextInputClient

extension TextView: @preconcurrency NSTextInputClient {
    public func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        if let marked = composingRange {
            // Committing marked text (e.g. "´" + "e" -> "é") replaces the marked run, not the selection.
            composingRange = nil
            replace(marked, with: text)
            return
        }
        if replacementRange.location != NSNotFound, let range = Range(replacementRange) {
            typingRun = nil
            replace(range, with: text)
            return
        }
        insertTyped(text)
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        let target = composingRange
            ?? (replacementRange.location != NSNotFound ? Range(replacementRange) : nil)
            ?? selection.range
        typingRun = nil
        replace(target, with: text, registerUndo: composingRange == nil)
        composingRange = text.isEmpty ? nil : target.lowerBound..<(target.lowerBound + text.utf16.count)
        if let composingRange, let inner = Range(selectedRange) {
            let start = composingRange.lowerBound + inner.lowerBound
            selection = TextSelection(anchor: start, head: start + inner.count)
        }
    }

    public func unmarkText() {
        composingRange = nil
        needsDisplay = true
    }

    public func selectedRange() -> NSRange { NSRange(selection.range) }

    public func markedRange() -> NSRange {
        composingRange.map { NSRange($0) } ?? NSRange(location: NSNotFound, length: 0)
    }

    public func hasMarkedText() -> Bool { composingRange != nil }

    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let proposed = Range(range) else { return nil }
        let clamped = proposed.clamped(to: 0..<layoutManager.storage.utf16Count)
        actualRange?.pointee = NSRange(clamped)
        return NSAttributedString(string: String(layoutManager.storage.substring(clamped)))
    }

    public func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let offset = range.location == NSNotFound ? selection.head : range.location
        let rect = layoutManager.caretRect(at: offset).offsetBy(dx: textInset, dy: 0)
        actualRange?.pointee = NSRange(location: offset, length: 0)
        guard let window else { return rect }
        return window.convertToScreen(convert(rect, to: nil))
    }

    public func characterIndex(for screenPoint: NSPoint) -> Int {
        guard let window else { return NSNotFound }
        let point = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        return offset(at: point)
    }
}
