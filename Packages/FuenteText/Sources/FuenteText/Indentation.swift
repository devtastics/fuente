/// How one level of indentation is written.
public enum Indentation: Equatable, Sendable {
    case tabs
    case spaces(Int)

    /// The text of one indentation level.
    public var unit: String {
        switch self {
        case .tabs: "\t"
        case .spaces(let count): String(repeating: " ", count: max(1, count))
        }
    }
}
