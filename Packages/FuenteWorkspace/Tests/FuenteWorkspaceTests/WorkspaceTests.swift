import Foundation
import Testing
@testable import FuenteWorkspace

/// A throwaway folder tree: src/{main.php, Util/helpers.php}, README.md, .hidden, zeta.txt
@MainActor
private func makeProject() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("fuente-ws-\(UUID().uuidString)")
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("src/Util"), withIntermediateDirectories: true)
    try "<?php".write(to: root.appendingPathComponent("src/main.php"), atomically: true, encoding: .utf8)
    try "<?php // helpers".write(to: root.appendingPathComponent("src/Util/helpers.php"), atomically: true, encoding: .utf8)
    try "# Readme".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    try "secret".write(to: root.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)
    try "z".write(to: root.appendingPathComponent("zeta.txt"), atomically: true, encoding: .utf8)
    return root
}

@Suite @MainActor struct FileNodeTests {
    @Test func listsFoldersFirstThenByNameSkippingHidden() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let node = FileNode(url: root, isDirectory: true)
        #expect(node.children.map(\.name) == ["src", "README.md", "zeta.txt"])
        #expect(node.children[0].isDirectory)
        #expect(node.children[0].children.map(\.name) == ["Util", "main.php"])
        #expect(node.children[0].children[0].parent === node.children[0])
    }

    @Test func findsNestedNodeAndRejectsOutsiders() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let node = FileNode(url: root, isDirectory: true)
        let helpers = node.node(for: root.appendingPathComponent("src/Util/helpers.php"))
        #expect(helpers?.name == "helpers.php")
        #expect(helpers?.isDirectory == false)
        #expect(node.node(for: root.appendingPathComponent("missing.txt")) == nil)
        #expect(node.node(for: FileManager.default.temporaryDirectory) == nil)
    }

    @Test func reloadPicksUpNewFiles() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let node = FileNode(url: root, isDirectory: true)
        #expect(node.children.count == 3)
        try "new".write(to: root.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        #expect(node.children.count == 3)
        node.reload()
        #expect(node.children.count == 4)
    }
}

@Suite @MainActor struct WorkspaceDocumentTests {
    @Test func opensActivatesAndDeduplicates() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(rootURL: root)
        let main = try workspace.open(root.appendingPathComponent("src/main.php"))
        let readme = try workspace.open(root.appendingPathComponent("README.md"))
        #expect(workspace.documents.count == 2)
        #expect(workspace.activeDocument === readme)
        #expect(try workspace.open(root.appendingPathComponent("src/main.php")) === main)
        #expect(workspace.documents.count == 2)
        #expect(workspace.activeDocument === main)
        #expect(main.savedText == "<?php")
    }

    @Test func closingPicksANeighbor() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(rootURL: root)
        let a = try workspace.open(root.appendingPathComponent("src/main.php"))
        let b = try workspace.open(root.appendingPathComponent("README.md"))
        let c = try workspace.open(root.appendingPathComponent("zeta.txt"))
        workspace.activate(b)
        workspace.close(b)
        #expect(workspace.activeDocument === c)
        workspace.close(c)
        #expect(workspace.activeDocument === a)
        workspace.close(a)
        #expect(workspace.activeDocument == nil)
    }

    @Test func containsAndSaveRoundTrip() throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(rootURL: root)
        #expect(workspace.contains(root.appendingPathComponent("src/main.php")))
        #expect(!workspace.contains(FileManager.default.temporaryDirectory.appendingPathComponent("x")))

        let doc = try workspace.open(root.appendingPathComponent("zeta.txt"))
        doc.markDirty()
        #expect(workspace.hasUnsavedChanges)
        try doc.save("zz")
        #expect(!doc.isDirty)
        #expect(try String(contentsOf: root.appendingPathComponent("zeta.txt"), encoding: .utf8) == "zz")
    }

    @Test func untitledDocumentNeedsALocation() throws {
        let doc = try Document(url: nil)
        #expect(doc.name == "Untitled")
        #expect(throws: DocumentError.noLocation) { try doc.save("x") }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("fuente-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: target) }
        try doc.save("x", to: target)
        #expect(doc.url == target.standardizedFileURL)
        #expect(doc.name == target.lastPathComponent)
    }
}
