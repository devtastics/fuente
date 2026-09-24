/// A single selection: `anchor` is where it started, `head` is where the caret is.
/// When both are equal the selection is just a caret.
public struct TextSelection: Equatable, Sendable {
    public var anchor: Int
    public var head: Int

    public init(caret: Int) {
        anchor = caret
        head = caret
    }

    public init(anchor: Int, head: Int) {
        self.anchor = anchor
        self.head = head
    }

    public var range: Range<Int> { min(anchor, head)..<max(anchor, head) }
    public var isEmpty: Bool { anchor == head }
}
