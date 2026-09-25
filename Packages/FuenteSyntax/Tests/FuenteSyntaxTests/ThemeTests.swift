import AppKit
import Testing
@testable import FuenteSyntax

@Suite struct ThemeTests {
    @Test func fallsBackAlongDots() {
        let theme = Theme(colors: ["keyword": .red, "function.builtin": .blue])
        #expect(theme.color(for: "keyword.operator") == .red)
        #expect(theme.color(for: "function.builtin") == .blue)
        #expect(theme.color(for: "function") == nil)
        #expect(theme.color(for: "variable") == nil)
    }

    @Test func languageLookupByExtension() {
        #expect(Languages.language(forFileExtension: "PHP")?.name == "PHP")
        #expect(Languages.language(forFileExtension: "swift") == nil)
    }
}
