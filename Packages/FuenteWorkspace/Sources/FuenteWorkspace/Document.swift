import Foundation

/// One open file. The editor owns the live text; the document knows where it lives and whether it is dirty.
@MainActor
public final class Document: Identifiable {
    nonisolated public let id = UUID()
    public private(set) var url: URL?
    public private(set) var isDirty = false

    /// Contents as last loaded from or written to disk.
    public private(set) var savedText: String

    public init(url: URL?) throws {
        self.url = url?.standardizedFileURL
        savedText = try url.map { try String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    public var name: String { url?.lastPathComponent ?? "Untitled" }
    public var fileExtension: String? { url?.pathExtension }

    public func markDirty() {
        isDirty = true
    }

    /// Writes `text` to `url`, or to `newURL` when given (Save As, or first save of an untitled document).
    public func save(_ text: String, to newURL: URL? = nil) throws {
        if let newURL { url = newURL.standardizedFileURL }
        guard let url else { throw DocumentError.noLocation }
        try text.write(to: url, atomically: true, encoding: .utf8)
        savedText = text
        isDirty = false
    }
}

public enum DocumentError: Error, Equatable {
    case noLocation
}
