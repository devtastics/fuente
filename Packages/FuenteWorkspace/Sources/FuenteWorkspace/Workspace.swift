import Foundation

/// A project: a root folder, its file tree and the documents open in it.
@MainActor
public final class Workspace {
    public let rootURL: URL
    public let root: FileNode
    public private(set) var documents: [Document] = []
    public private(set) var activeDocument: Document?

    public var name: String { rootURL.lastPathComponent }

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
        self.root = FileNode(url: rootURL, isDirectory: true)
    }

    public func contains(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(rootURL.path + "/")
    }

    public func document(for url: URL) -> Document? {
        let url = url.standardizedFileURL
        return documents.first { $0.url == url }
    }

    /// Opens a file, or activates it if already open.
    @discardableResult
    public func open(_ url: URL) throws -> Document {
        let document = try self.document(for: url) ?? {
            let created = try Document(url: url)
            documents.append(created)
            return created
        }()
        activeDocument = document
        return document
    }

    public func activate(_ document: Document) {
        guard documents.contains(where: { $0 === document }) else { return }
        activeDocument = document
    }

    /// Closes a document. The neighbor becomes active when the closed one was.
    public func close(_ document: Document) {
        guard let index = documents.firstIndex(where: { $0 === document }) else { return }
        documents.remove(at: index)
        if activeDocument === document {
            activeDocument = documents.isEmpty ? nil : documents[min(index, documents.count - 1)]
        }
    }

    public var hasUnsavedChanges: Bool { documents.contains { $0.isDirty } }
}
