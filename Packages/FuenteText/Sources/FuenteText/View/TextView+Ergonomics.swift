import AppKit

/// Editing conveniences: word/line selection, comment toggling, indenting, line moves, bracket pairs.
/// Every compound edit is one undo step.
extension TextView {
    // MARK: - Character classes

    static func isIdentifier(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || unit == 0x5F // _
    }

    static func isWhitespace(_ unit: UInt16) -> Bool { unit == 0x20 || unit == 0x09 }

    /// UTF-16 range of the word (identifier run, or run of one punctuation class) around `offset`.
    public func wordRange(at offset: Int) -> Range<Int> {
        let storage = layoutManager.storage
        let lineRange = storage.lineRange(storage.line(at: offset))
        let units = Array(storage.substring(lineRange).utf16)
        guard !units.isEmpty else { return offset..<offset }
        var local = min(max(offset - lineRange.lowerBound, 0), units.count)
        if local == units.count { local -= 1 }
        let unit = units[local]
        let sameClass: (UInt16) -> Bool
        if Self.isIdentifier(unit) { sameClass = Self.isIdentifier }
        else if Self.isWhitespace(unit) { sameClass = Self.isWhitespace }
        else { return (lineRange.lowerBound + local)..<(lineRange.lowerBound + local + 1) }
        var start = local, end = local + 1
        while start > 0, sameClass(units[start - 1]) { start -= 1 }
        while end < units.count, sameClass(units[end]) { end += 1 }
        return (lineRange.lowerBound + start)..<(lineRange.lowerBound + end)
    }

    /// The line containing `offset`, including its newline.
    func fullLineRange(at offset: Int) -> Range<Int> {
        let storage = layoutManager.storage
        let line = storage.line(at: offset)
        let end = line + 1 < storage.lineCount ? storage.lineStarts[line + 1] : storage.utf16Count
        return storage.lineStarts[line]..<end
    }

    /// Lines touched by the selection, as a closed range of line indices.
    var selectedLines: ClosedRange<Int> {
        let storage = layoutManager.storage
        let range = selection.range
        let first = storage.line(at: range.lowerBound)
        // A selection ending exactly at a line start does not include that line.
        let lastOffset = range.isEmpty ? range.upperBound : max(range.lowerBound, range.upperBound - 1)
        return first...storage.line(at: lastOffset)
    }

    /// Runs `body` as a single undo step and breaks any typing run.
    func performGrouped(_ body: () -> Void) {
        typingRun = nil
        textUndoManager.beginUndoGrouping()
        body()
        textUndoManager.endUndoGrouping()
    }

    // MARK: - Indentation of selected lines

    @objc public func shiftRight(_ sender: Any?) {
        let storage = layoutManager.storage
        let lines = selectedLines
        let unit = indentation.unit
        let anchorLine = storage.line(at: selection.anchor), headLine = storage.line(at: selection.head)
        let anchorColumn = selection.anchor - storage.lineStarts[anchorLine], headColumn = selection.head - storage.lineStarts[headLine]
        performGrouped {
            for line in lines.reversed() {
                let start = layoutManager.storage.lineStarts[line]
                replace(start..<start, with: unit, registerUndo: true)
            }
            let s = layoutManager.storage
            selection = TextSelection(anchor: s.lineStarts[anchorLine] + anchorColumn + unit.utf16.count,
                                      head: s.lineStarts[headLine] + headColumn + unit.utf16.count)
        }
    }

    @objc public func shiftLeft(_ sender: Any?) {
        let lines = selectedLines
        let width = indentation.unit.utf16.count
        var removedAtAnchor = 0, removedAtHead = 0
        let storage0 = layoutManager.storage
        let anchorLine = storage0.line(at: selection.anchor), headLine = storage0.line(at: selection.head)
        let anchorColumn = selection.anchor - storage0.lineStarts[anchorLine], headColumn = selection.head - storage0.lineStarts[headLine]
        performGrouped {
            for line in lines.reversed() {
                let storage = layoutManager.storage
                let range = storage.lineRange(line)
                let units = Array(storage.substring(range).utf16)
                var count = 0
                if units.first == 0x09 { count = 1 } else { while count < min(width, units.count), units[count] == 0x20 { count += 1 } }
                guard count > 0 else { continue }
                replace(range.lowerBound..<(range.lowerBound + count), with: "", registerUndo: true)
                if line == anchorLine { removedAtAnchor = min(count, anchorColumn) }
                if line == headLine { removedAtHead = min(count, headColumn) }
            }
            let s = layoutManager.storage
            selection = TextSelection(anchor: s.lineStarts[anchorLine] + anchorColumn - removedAtAnchor,
                                      head: s.lineStarts[headLine] + headColumn - removedAtHead)
        }
    }

    /// Tab indents selected lines; with a caret it inserts one indentation unit.
    public override func insertTab(_ sender: Any?) {
        if selection.isEmpty { insertTyped(indentation.unit) } else { shiftRight(sender) }
    }

    public override func insertBacktab(_ sender: Any?) {
        shiftLeft(sender)
    }

    // MARK: - Comments

    /// Adds the line comment prefix to the selected lines, or removes it when every non-blank line has one.
    @objc public func toggleComment(_ sender: Any?) {
        guard let prefix = lineCommentPrefix else { return }
        let storage = layoutManager.storage
        let lines = selectedLines
        var contents: [(line: Int, text: [UInt16], indent: Int)] = []
        for line in lines {
            let text = Array(storage.lineContent(line).utf16)
            let indent = text.prefix { Self.isWhitespace($0) }.count
            contents.append((line, text, indent))
        }
        let nonBlank = contents.filter { $0.text.count > $0.indent }
        let prefixUnits = Array(prefix.utf16)
        let allCommented = !nonBlank.isEmpty && nonBlank.allSatisfy { Array($0.text.dropFirst($0.indent).prefix(prefixUnits.count)) == prefixUnits }
        let column = nonBlank.map(\.indent).min() ?? 0
        let anchorLine = storage.line(at: selection.anchor), headLine = storage.line(at: selection.head)
        var anchorColumn = selection.anchor - storage.lineStarts[anchorLine], headColumn = selection.head - storage.lineStarts[headLine]

        performGrouped {
            for entry in contents.reversed() {
                let start = layoutManager.storage.lineStarts[entry.line]
                var delta = 0
                let hasPrefix = Array(entry.text.dropFirst(entry.indent).prefix(prefixUnits.count)) == prefixUnits
                if allCommented, hasPrefix {
                    let after = entry.text.dropFirst(entry.indent + prefixUnits.count)
                    let extraSpace = after.first == 0x20 ? 1 : 0
                    let removed = prefixUnits.count + extraSpace
                    replace((start + entry.indent)..<(start + entry.indent + removed), with: "", registerUndo: true)
                    delta = -removed
                } else if !allCommented, entry.text.count > entry.indent {
                    replace((start + column)..<(start + column), with: prefix + " ", registerUndo: true)
                    delta = prefixUnits.count + 1
                }
                if entry.line == anchorLine, anchorColumn >= entry.indent { anchorColumn = max(entry.indent, anchorColumn + delta) }
                if entry.line == headLine, headColumn >= entry.indent { headColumn = max(entry.indent, headColumn + delta) }
            }
            let s = layoutManager.storage
            selection = TextSelection(anchor: s.lineStarts[anchorLine] + anchorColumn, head: s.lineStarts[headLine] + headColumn)
        }
    }

    // MARK: - Line moves

    @objc public func duplicateLine(_ sender: Any?) {
        let storage = layoutManager.storage
        let lines = selectedLines
        let start = storage.lineStarts[lines.lowerBound]
        let end = fullLineRange(at: storage.lineStarts[lines.upperBound]).upperBound
        var block = storage.substring(start..<end)
        if !block.hasSuffix("\n") { block = "\n" + block }   // last line without newline
        let insertAt = block.hasPrefix("\n") ? end : end
        let shift = block.utf16.count
        let anchor = selection.anchor, head = selection.head
        performGrouped {
            replace(insertAt..<insertAt, with: block, registerUndo: true)
            selection = TextSelection(anchor: anchor + shift, head: head + shift)
        }
    }

    @objc public func moveLineUp(_ sender: Any?) { moveSelectedLines(by: -1) }
    @objc public func moveLineDown(_ sender: Any?) { moveSelectedLines(by: 1) }

    private func moveSelectedLines(by direction: Int) {
        let storage = layoutManager.storage
        let lines = selectedLines
        let target = direction < 0 ? lines.lowerBound - 1 : lines.upperBound + 1
        guard target >= 0, target < storage.lineCount else { return }
        let blockStart = storage.lineStarts[lines.lowerBound]
        let blockEnd = storage.lineRange(lines.upperBound).upperBound
        let block = storage.substring(blockStart..<blockEnd)
        let neighbor = storage.lineContent(target)
        let anchorOffset = selection.anchor - blockStart, headOffset = selection.head - blockStart
        performGrouped {
            if direction < 0 {
                let neighborStart = layoutManager.storage.lineStarts[target]
                replace(neighborStart..<blockEnd, with: block + "\n" + neighbor, registerUndo: true)
                selection = TextSelection(anchor: neighborStart + anchorOffset, head: neighborStart + headOffset)
            } else {
                let neighborEnd = layoutManager.storage.lineRange(target).upperBound
                replace(blockStart..<neighborEnd, with: neighbor + "\n" + block, registerUndo: true)
                let newStart = blockStart + neighbor.utf16.count + 1
                selection = TextSelection(anchor: newStart + anchorOffset, head: newStart + headOffset)
            }
        }
    }

    // MARK: - Go to line

    /// Places the caret at the start of a 1-based line and scrolls there.
    public func goToLine(_ line: Int) {
        let storage = layoutManager.storage
        let index = min(max(line - 1, 0), storage.lineCount - 1)
        selection = TextSelection(caret: storage.lineStarts[index])
        scrollToVisible(caretRect.insetBy(dx: 0, dy: -bounds.height / 3))
    }

    // MARK: - Bracket pairs

    static let openers: [UInt16: UInt16] = [0x28: 0x29, 0x5B: 0x5D, 0x7B: 0x7D]   // ( [ {
    static let closers: [UInt16: UInt16] = [0x29: 0x28, 0x5D: 0x5B, 0x7D: 0x7B]
    static let quotes: Set<UInt16> = [0x22, 0x27, 0x60]                            // " ' `

    func unit(at offset: Int) -> UInt16? {
        let storage = layoutManager.storage
        guard offset >= 0, offset < storage.utf16Count else { return nil }
        return storage.substring(offset..<(offset + 1)).utf16.first
    }

    /// The bracket adjacent to the caret (before it first, then at it) and its match, if any.
    public func matchingBracketRanges(at offset: Int) -> (Range<Int>, Range<Int>)? {
        for candidate in [offset - 1, offset] {
            guard let unit = unit(at: candidate) else { continue }
            if let closer = Self.openers[unit], let match = scanBracket(from: candidate, open: unit, close: closer, forward: true) {
                return (candidate..<(candidate + 1), match..<(match + 1))
            }
            if let opener = Self.closers[unit], let match = scanBracket(from: candidate, open: opener, close: unit, forward: false) {
                return (candidate..<(candidate + 1), match..<(match + 1))
            }
        }
        return nil
    }

    /// Depth-counting scan, bounded so a stray bracket in a huge file cannot stall the main thread.
    private func scanBracket(from start: Int, open: UInt16, close: UInt16, forward: Bool, limit: Int = 200_000) -> Int? {
        let storage = layoutManager.storage
        let range = forward ? (start + 1)..<min(storage.utf16Count, start + 1 + limit) : max(0, start - limit)..<start
        guard !range.isEmpty else { return nil }
        let units = Array(storage.substring(range).utf16)
        var depth = 0
        if forward {
            for (index, unit) in units.enumerated() {
                if unit == open { depth += 1 } else if unit == close { if depth == 0 { return range.lowerBound + index }; depth -= 1 }
            }
        } else {
            for index in stride(from: units.count - 1, through: 0, by: -1) {
                let unit = units[index]
                if unit == close { depth += 1 } else if unit == open { if depth == 0 { return range.lowerBound + index }; depth -= 1 }
            }
        }
        return nil
    }

    /// Handles a typed opener, closer or quote. Returns true when it consumed the keystroke.
    func handleAutoPair(_ text: String) -> Bool {
        guard autoClosesPairs, text.utf16.count == 1, let typed = text.utf16.first else { return false }
        let range = selection.range
        let next = unit(at: range.upperBound)
        let previous = unit(at: range.lowerBound - 1)
        let nextIsBoundary = next == nil || next == 0x0A || Self.isWhitespace(next!) || Self.closers[next!] != nil

        if let closer = Self.openers[typed] {
            let close = String(utf16CodeUnits: [closer], count: 1)
            if !range.isEmpty {
                wrap(range, open: text, close: close)
                return true
            }
            guard nextIsBoundary else { return false }
            performGrouped {
                replace(range, with: text + close, selectionAfter: TextSelection(caret: range.lowerBound + 1), registerUndo: true)
            }
            return true
        }
        if Self.closers[typed] != nil || Self.quotes.contains(typed) {
            if range.isEmpty, next == typed {
                selection = TextSelection(caret: range.lowerBound + 1)   // step over the existing closer
                return true
            }
        }
        if Self.quotes.contains(typed) {
            if !range.isEmpty {
                wrap(range, open: text, close: text)
                return true
            }
            guard nextIsBoundary, previous == nil || !Self.isIdentifier(previous!), previous != typed else { return false }
            performGrouped {
                replace(range, with: text + text, selectionAfter: TextSelection(caret: range.lowerBound + 1), registerUndo: true)
            }
            return true
        }
        return false
    }

    private func wrap(_ range: Range<Int>, open: String, close: String) {
        let inner = layoutManager.storage.substring(range)
        performGrouped {
            replace(range, with: open + inner + close,
                    selectionAfter: TextSelection(anchor: range.lowerBound + 1, head: range.lowerBound + 1 + inner.utf16.count), registerUndo: true)
        }
    }

    /// Backspace between an empty pair removes both characters. Returns true when it did.
    func deleteEmptyPairIfNeeded() -> Bool {
        guard autoClosesPairs, selection.isEmpty, let previous = unit(at: selection.head - 1), let next = unit(at: selection.head) else { return false }
        let isPair = Self.openers[previous] == next || (Self.quotes.contains(previous) && previous == next)
        guard isPair else { return false }
        performGrouped { replace((selection.head - 1)..<(selection.head + 1), with: "", registerUndo: true) }
        return true
    }

    /// Return between `{` and `}` puts the closer on its own line and the caret on an indented line between.
    func openBlockOnNewlineIfNeeded() -> Bool {
        guard autoClosesPairs, selection.isEmpty, unit(at: selection.head - 1) == 0x7B, unit(at: selection.head) == 0x7D else { return false }
        let storage = layoutManager.storage
        let lineStart = storage.lineStarts[storage.line(at: selection.head)]
        let leading = String(storage.substring(lineStart..<selection.head).prefix { $0 == " " || $0 == "\t" })
        let caret = selection.head
        performGrouped {
            replace(caret..<caret, with: "\n" + leading + indentation.unit + "\n" + leading,
                    selectionAfter: TextSelection(caret: caret + 1 + leading.utf16.count + indentation.unit.utf16.count), registerUndo: true)
        }
        return true
    }
}
