import Testing
@testable import PortlyCore

struct FreePortFinderTests {

    @Test func suggestsFirstPortInRangeWhenNoneUsed() {
        #expect(FreePortFinder.suggest(excluding: [], ranges: [3000...3005]) == 3000)
    }

    @Test func skipsUsedPortsWithinARange() {
        #expect(FreePortFinder.suggest(excluding: [3000, 3001], ranges: [3000...3005]) == 3002)
    }

    @Test func fallsThroughToTheNextRangeWhenTheFirstIsFull() {
        let full = Set(3000...3005)
        #expect(FreePortFinder.suggest(excluding: full, ranges: [3000...3005, 5000...5005]) == 5000)
    }

    @Test func returnsNilWhenEveryRangeIsFull() {
        let full = Set(3000...3005).union(5000...5005)
        #expect(FreePortFinder.suggest(excluding: full, ranges: [3000...3005, 5000...5005]) == nil)
    }
}
