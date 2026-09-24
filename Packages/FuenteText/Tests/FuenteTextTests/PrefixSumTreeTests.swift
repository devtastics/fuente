import Testing
@testable import FuenteText

@Suite struct PrefixSumTreeTests {
    @Test func sumsAndUpdates() {
        var tree = PrefixSumTree([10, 20, 30, 40, 50])
        #expect(tree.sum(upTo: 0) == 0)
        #expect(tree.sum(upTo: 3) == 60)
        #expect(tree.total == 150)
        tree.add(5, at: 1)
        #expect(tree.sum(upTo: 2) == 35)
        #expect(tree.total == 155)
    }

    @Test func lookupByValueMatchesPrefixSums() {
        let tree = PrefixSumTree([10, 20, 30, 40, 50, 60, 70])
        for index in 0..<7 {
            let start = tree.sum(upTo: index)
            #expect(tree.index(containing: start) == index)
            #expect(tree.index(containing: start + 5) == index)
        }
        #expect(tree.index(containing: -1) == 0)
        #expect(tree.index(containing: 10_000) == 6)
    }

    @Test func emptyTree() {
        let tree = PrefixSumTree([])
        #expect(tree.total == 0)
        #expect(tree.index(containing: 5) == 0)
    }
}
