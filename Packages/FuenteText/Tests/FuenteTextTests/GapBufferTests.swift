import Testing
@testable import FuenteText

@Suite struct GapBufferTests {
    @Test func replacementsMatchAPlainArrayOracle() {
        var oracle: [UInt16] = Array("hello world".utf16)
        var buffer = GapBuffer(oracle)
        // A fixed pseudo-random sequence: deterministic, exercises gap moves in both directions and growth.
        var seed: UInt64 = 42
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return bound == 0 ? 0 : Int(seed >> 33) % bound
        }
        for step in 0..<2000 {
            let start = next(oracle.count + 1)
            let length = next(min(5, oracle.count - start) + 1)
            let text = step % 7 == 0 ? String(repeating: "abcdefgh", count: 40) : String(UnicodeScalar(UInt8(97 + step % 26)))
            let units = Array(text.utf16)
            oracle.replaceSubrange(start..<(start + length), with: units)
            buffer.replace(start..<(start + length), with: units)
            #expect(buffer.count == oracle.count)
        }
        #expect(buffer.all == oracle)
        #expect(buffer.copy(10..<40) == Array(oracle[10..<40]))
        #expect(buffer[7] == oracle[7])
    }

    @Test func emptyAndEdgeCases() {
        var buffer = GapBuffer([])
        #expect(buffer.count == 0 && buffer.all.isEmpty)
        buffer.replace(0..<0, with: Array("ab".utf16))
        buffer.replace(0..<0, with: Array("x".utf16))      // insert at start: gap moves left
        buffer.replace(3..<3, with: Array("y".utf16))      // insert at end: gap moves right
        #expect(String(decoding: buffer.all, as: UTF16.self) == "xaby")
        buffer.replace(0..<4, with: [])
        #expect(buffer.count == 0)
    }
}
