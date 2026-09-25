import Foundation

/// One open file. The editor owns the live text; the document knows where it lives, whether it is dirty,
/// and when the file on disk was last seen. It never keeps a copy of the text.
@MainActor
public final class Document: Identifiable {
    nonisolated public let id = UUID()
    public private(set) var url: URL?
    public private(set) var isDirty = false

    /// Modification date of the file when we last read or wrote it, to notice outside changes.
    public private(set) var diskModificationDate: Date?

    public init(url: URL?) {
        self.url = url?.standardizedFileURL
        diskModificationDate = url.flatMap(Document.modificationDate)
    }

    /// Reads the file now. Untitled documents are empty. The caller owns the text; nothing is retained.
    public func read() throws -> String {
        guard let url else { return "" }
        let text = try String(contentsOf: url, encoding: .utf8)
        diskModificationDate = Document.modificationDate(of: url)
        return text
    }

    /// Through FileManager on purpose: URL resource values are cached per URL instance and would go stale.
    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// True when the file on disk is newer than what we last read or wrote.
    public var hasChangedOnDisk: Bool {
        guard let url, let onDisk = Document.modificationDate(of: url) else { return false }
        return onDisk != diskModificationDate
    }

    /// Re-reads the file. The caller puts the returned text in the editor. Clears the dirty flag.
    public func reloadFromDisk() throws -> String {
        guard url != nil else { throw DocumentError.noLocation }
        let text = try read()
        isDirty = false
        return text
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
        diskModificationDate = Document.modificationDate(of: url)
        isDirty = false
    }
}

public enum DocumentError: Error, Equatable {
    case noLocation
    case unreadable(URL)
}
