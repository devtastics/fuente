import AppKit

/// Maps capture names to colors. `keyword.operator` falls back to `keyword` when not set.
public struct Theme {
    public var colors: [String: NSColor]

    public init(colors: [String: NSColor]) {
        self.colors = colors
    }

    public func color(for capture: String) -> NSColor? {
        var name = Substring(capture)
        while true {
            if let color = colors[String(name)] { return color }
            guard let dot = name.lastIndex(of: ".") else { return nil }
            name = name[..<dot]
        }
    }

    /// Dynamic system colors, so one theme follows light and dark appearance.
    @MainActor public static let system = Theme(colors: [
        "keyword": .systemPink,
        "string": .systemRed,
        "number": .systemBlue,
        "comment": .systemGray,
        "type": .systemPurple,
        "constructor": .systemPurple,
        "function": .systemTeal,
        "constant": .systemIndigo,
        "variable.builtin": .systemPurple,
        "property": .systemCyan,
        "operator": .secondaryLabelColor,
        "tag": .systemOrange,
        "module": .systemBrown,
    ])
}
