import AppKit
import Testing
@testable import FuenteText

@Suite struct LineTypesetterTests {
    let typesetter = LineTypesetter(font: NSFont(name: "Menlo", size: 12)!)

    @Test func unwrappedLineIsOneFragment() {
        let fragments = typesetter.typeset("echo 'hola';")
        #expect(fragments.count == 1)
        #expect(fragments[0].range == 0..<12)
        #expect(fragments[0].width > 0)
        #expect(fragments[0].height > 0)
    }

    @Test func emptyLineStillHasHeight() {
        let fragments = typesetter.typeset("")
        #expect(fragments.count == 1)
        #expect(fragments[0].range == 0..<0)
        #expect(fragments[0].height > 0)
    }

    @Test func wrappedFragmentsAreContiguousAndFit() {
        let text = String(repeating: "a", count: 200)
        let width: CGFloat = 100
        let fragments = typesetter.typeset(text, width: width)

        #expect(fragments.count > 1)
        #expect(fragments.first?.range.lowerBound == 0)
        #expect(fragments.last?.range.upperBound == 200)
        for (previous, next) in zip(fragments, fragments.dropFirst()) {
            #expect(previous.range.upperBound == next.range.lowerBound)
        }
        for fragment in fragments {
            #expect(fragment.width <= width)
        }
    }

    @Test func narrowWidthStillConsumesText() {
        let fragments = typesetter.typeset("abc", width: 1)
        #expect(fragments.count == 3)
    }

    @Test func offsetToXRoundTrips() {
        let fragment = typesetter.typeset("abcdef")[0]
        #expect(fragment.xOffset(for: 0) == 0)
        var last: CGFloat = -1
        for offset in 0...6 {
            let x = fragment.xOffset(for: offset)
            #expect(x > last)
            #expect(fragment.offset(forX: x) == offset)
            last = x
        }
    }
}
