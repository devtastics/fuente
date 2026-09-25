import TreeSitterPHP

/// The grammars bundled with Fuente. One vendored package each under `Packages/Grammars`.
public enum Languages {
    public static let php = Language(
        name: "PHP",
        fileExtensions: ["php", "phtml", "inc"],
        pointer: PHPGrammar.language,
        highlightsQuery: PHPGrammar.highlightsQuery
    )

    public static let all: [Language] = [php]

    public static func language(forFileExtension ext: String) -> Language? {
        let lowered = ext.lowercased()
        return all.first { $0.fileExtensions.contains(lowered) }
    }
}
