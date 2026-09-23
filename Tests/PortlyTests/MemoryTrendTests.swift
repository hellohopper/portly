import Testing
@testable import PortlyCore

struct MemoryTrendTests {

    @Test func recordsPerPidAndForgetsDeadProcesses() {
        var trend = MemoryTrend()
        trend.record([1: 100, 2: 200])
        trend.record([1: 150])
        #expect(trend.history(for: 1) == [100, 150])
        #expect(trend.history(for: 2).isEmpty)
    }

    @Test func capsTheWindow() {
        var trend = MemoryTrend()
        for value in 1...(MemoryTrend.sampleLimit + 5) {
            trend.record([7: UInt64(value)])
        }
        #expect(trend.history(for: 7).count == MemoryTrend.sampleLimit)
        #expect(trend.history(for: 7).first == 6)
    }

    @Test func steadyGrowthLooksLikeALeak() {
        let history = (0..<10).map { 300.0 + Double($0) * 40 } // 300 -> 660
        #expect(MemoryTrend.isGrowing(history))
    }

    @Test func flatSawtoothOrShortHistoriesDoNot() {
        #expect(!MemoryTrend.isGrowing([300, 310, 305, 300, 315, 300, 310, 305, 300, 310]))
        #expect(!MemoryTrend.isGrowing([100, 200, 400]))
        // Grew, but mostly by falling and jumping -- churn, not a steady climb.
        #expect(!MemoryTrend.isGrowing([100, 400, 150, 420, 160, 440, 170, 460, 180, 500]))
    }
}
