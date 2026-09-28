import Foundation
import Testing
@testable import FuenteWorkspace

@Suite struct ProjectSearchTests {
    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fuente-search-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("vendor/lib"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "<?php\nfunction foo() {}\n$Foo = foo(); // foobar\n".write(to: root.appendingPathComponent("src/a.php"), atomically: true, encoding: .utf8)
        try "no hits here\n".write(to: root.appendingPathComponent("src/b.txt"), atomically: true, encoding: .utf8)
        try "foo in vendor\n".write(to: root.appendingPathComponent("vendor/lib/c.php"), atomically: true, encoding: .utf8)
        try "foo in git\n".write(to: root.appendingPathComponent(".git/config"), atomically: true, encoding: .utf8)
        try Data([0x66, 0x6F, 0x6F, 0x00, 0x01]).write(to: root.appendingPathComponent("blob.bin"))  // "foo" then NUL
        return root
    }

    private func collect(_ search: ProjectSearch, _ query: SearchQuery) async -> [SearchFileResult] {
        var results: [SearchFileResult] = []
        for await result in search.results(for: query) { results.append(result) }
        return results.sorted { $0.url.path < $1.url.path }
    }

    @Test func findsMatchesPerLineCaseInsensitive() async throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let results = await collect(ProjectSearch(rootURL: root), SearchQuery(text: "foo"))
        #expect(results.map(\.url.lastPathComponent) == ["a.php"])            // vendor, .git and the binary are skipped
        let matches = results[0].matches
        #expect(matches.map(\.line) == [1, 2, 2, 2])
        #expect(matches[1].lineText == "$Foo = foo(); // foobar")
        #expect(matches[1].range == 1..<4)                                      // "Foo" matched case-insensitively
        #expect(matches[3].range == 17..<20)                                    // inside "foobar"
    }

    @Test func caseWholeWordAndRegexOptions() async throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        let search = ProjectSearch(rootURL: root)
        let sensitive = await collect(search, SearchQuery(text: "foo", isCaseSensitive: true))
        #expect(sensitive[0].matches.count == 3)
        let whole = await collect(search, SearchQuery(text: "foo", matchesWholeWord: true))
        #expect(whole[0].matches.map(\.range) == [9..<12, 1..<4, 7..<10])       // not "foobar"
        let regex = await collect(search, SearchQuery(text: "fo+\\(\\)", isRegex: true))
        #expect(regex[0].matches.map(\.line) == [1, 2])
        #expect(await collect(search, SearchQuery(text: "[", isRegex: true)).isEmpty)  // invalid pattern: no results
        #expect(await collect(search, SearchQuery(text: "")).isEmpty)
    }

    @Test func excludedFoldersAreConfigurable() async throws {
        let root = try makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        var search = ProjectSearch(rootURL: root)
        search.excludedDirectoryNames = []
        let results = await collect(search, SearchQuery(text: "vendor"))
        #expect(results.map(\.url.lastPathComponent) == ["c.php"])
    }
}
