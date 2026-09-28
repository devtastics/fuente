import Foundation

/// What to look for.
public struct SearchQuery: Sendable, Equatable {
    public var text: String
    public var isCaseSensitive = false
    public var matchesWholeWord = false
    public var isRegex = false

    public init(text: String, isCaseSensitive: Bool = false, matchesWholeWord: Bool = false, isRegex: Bool = false) {
        self.text = text
        self.isCaseSensitive = isCaseSensitive
        self.matchesWholeWord = matchesWholeWord
        self.isRegex = isRegex
    }

    /// The compiled pattern, or `nil` for an empty query or an invalid regular expression.
    func regularExpression() -> NSRegularExpression? {
        guard !text.isEmpty else { return nil }
        var pattern = isRegex ? text : NSRegularExpression.escapedPattern(for: text)
        if matchesWholeWord { pattern = "\\b(?:\(pattern))\\b" }
        var options: NSRegularExpression.Options = []
        if !isCaseSensitive { options.insert(.caseInsensitive) }
        return try? NSRegularExpression(pattern: pattern, options: options)
    }
}

/// One hit: a file, a zero-based line, that line's text and the UTF-16 range of the match within it.
public struct SearchMatch: Sendable, Equatable {
    public let url: URL
    public let line: Int
    public let lineText: String
    public let range: Range<Int>
}

/// All hits in one file, in order.
public struct SearchFileResult: Sendable, Equatable {
    public let url: URL
    public let matches: [SearchMatch]
}

/// Searches the text files under a folder, off the main thread, streaming results file by file.
public struct ProjectSearch: Sendable {
    public var rootURL: URL

    /// Folder names never descended into. Hidden entries are always skipped.
    public var excludedDirectoryNames: Set<String> = ["node_modules", "vendor", ".build", "DerivedData", "Pods"]

    /// Files larger than this are skipped: they are almost always generated.
    public var maxFileSize = 4_000_000

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    /// Results arrive per file, in filesystem enumeration order. Cancelling the consuming task stops the search.
    public func results(for query: SearchQuery) -> AsyncStream<SearchFileResult> {
        AsyncStream { continuation in
            guard let regex = query.regularExpression() else {
                continuation.finish()
                return
            }
            let search = self
            let task = Task.detached(priority: .userInitiated) {
                search.run(regex: regex) { result in
                    continuation.yield(result)
                    return !Task.isCancelled
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Synchronous walk. `emit` returns false to stop early.
    func run(regex: NSRegularExpression, emit: (SearchFileResult) -> Bool) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .nameKey]
        guard let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true {
                if excludedDirectoryNames.contains(values.name ?? "") { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true, (values.fileSize ?? 0) <= maxFileSize else { continue }
            guard let matches = ProjectSearch.matches(in: url, regex: regex), !matches.isEmpty else { continue }
            if !emit(SearchFileResult(url: url.standardizedFileURL, matches: matches)) { return }
        }
    }

    /// `nil` for binary or unreadable files.
    static func matches(in url: URL, regex: NSRegularExpression) -> [SearchMatch]? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        if data.prefix(8192).contains(0) { return nil }   // NUL bytes: not text
        let text = String(decoding: data, as: UTF8.self)
        var results: [SearchMatch] = []
        var line = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            let lineText = String(text[range])
            let nsLine = lineText as NSString
            for match in regex.matches(in: lineText, range: NSRange(location: 0, length: nsLine.length)) where match.range.length > 0 {
                results.append(SearchMatch(url: url.standardizedFileURL, line: line, lineText: lineText, range: Range(match.range)!))
            }
            line += 1
        }
        return results
    }
}
