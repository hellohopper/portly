import Testing
@testable import Portly

struct ProcessMetricsResolverTests {

    @Test func energyLevelLowBelowFivePercent() {
        #expect(ProcessMetricsResolver.EnergyLevel.from(cpuPercent: 0) == .low)
        #expect(ProcessMetricsResolver.EnergyLevel.from(cpuPercent: 4.9) == .low)
    }

    @Test func energyLevelMediumBetweenFiveAndTwentyPercent() {
        #expect(ProcessMetricsResolver.EnergyLevel.from(cpuPercent: 5) == .medium)
        #expect(ProcessMetricsResolver.EnergyLevel.from(cpuPercent: 19.9) == .medium)
    }

    @Test func energyLevelHighAtOrAboveTwentyPercent() {
        #expect(ProcessMetricsResolver.EnergyLevel.from(cpuPercent: 20) == .high)
        #expect(ProcessMetricsResolver.EnergyLevel.from(cpuPercent: 100) == .high)
    }
}
