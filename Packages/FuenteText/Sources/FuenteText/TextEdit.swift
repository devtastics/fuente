/// A position as line and UTF-16 column. What incremental parsers need alongside plain offsets.
public struct TextPoint: Sendable, Equatable {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

/// One replacement, described the way tree-sitter's `TSInputEdit` wants it: where it started, where the
/// replaced text used to end, and where the new text ends. Offsets are UTF-16 code units.
public struct TextEdit: Sendable, Equatable {
    public let start: Int
    public let oldEnd: Int
    public let newEnd: Int
    public let startPoint: TextPoint
    public let oldEndPoint: TextPoint
    public let newEndPoint: TextPoint

    public init(start: Int, oldEnd: Int, newEnd: Int, startPoint: TextPoint, oldEndPoint: TextPoint, newEndPoint: TextPoint) {
        self.start = start
        self.oldEnd = oldEnd
        self.newEnd = newEnd
        self.startPoint = startPoint
        self.oldEndPoint = oldEndPoint
        self.newEndPoint = newEndPoint
    }
}
