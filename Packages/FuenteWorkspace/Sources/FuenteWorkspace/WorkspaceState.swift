import CryptoKit
import Foundation

/// What a project window remembers between sessions. Paths are relative to the project root, so the
/// state survives moving the folder and never leaks absolute paths into shared machines.
public struct WorkspaceState: Codable, Equatable, Sendable {
    public var openFiles: [String]
    public var activeFile: String?
    public var expandedFolders: [String]

    public init(openFiles: [String] = [], activeFile: String? = nil, expandedFolders: [String] = []) {
        self.openFiles = openFiles
        self.activeFile = activeFile
        self.expandedFolders = expandedFolders
    }
}

/// Reads and writes `WorkspaceState` files outside the project, one per root folder.
public struct WorkspaceStateStore: Sendable {
    public let directory: URL

    /// `~/Library/Application Support/Fuente/Workspaces`
    public static var `default`: WorkspaceStateStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return WorkspaceStateStore(directory: base.appendingPathComponent("Fuente/Workspaces", isDirectory: true))
    }

    public init(directory: URL) {
        self.directory = directory
    }

    public func fileURL(for rootURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(rootURL.standardizedFileURL.path.utf8))
        let name = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(name).json")
    }

    public func load(for rootURL: URL) -> WorkspaceState? {
        guard let data = try? Data(contentsOf: fileURL(for: rootURL)) else { return nil }
        return try? JSONDecoder().decode(WorkspaceState.self, from: data)
    }

    public func save(_ state: WorkspaceState, for rootURL: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL(for: rootURL), options: .atomic)
    }
}
