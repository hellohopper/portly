import Testing
@testable import PortlyCore

struct ByteRateFormatterTests {

    @Test func formatsBytesBelowOneKilobyte() {
        #expect(ByteRateFormatter.format(bytesPerSecond: 482) == "482B/s")
    }

    @Test func formatsKilobytes() {
        #expect(ByteRateFormatter.format(bytesPerSecond: 12_000) == "11.7KB/s")
    }

    @Test func formatsMegabytes() {
        #expect(ByteRateFormatter.format(bytesPerSecond: 3_400_000) == "3.2MB/s")
    }

    @Test func formatsZero() {
        #expect(ByteRateFormatter.format(bytesPerSecond: 0) == "0B/s")
    }

    @Test func formatsGigabytesWithoutOverflowingUnits() {
        #expect(ByteRateFormatter.format(bytesPerSecond: 2_500_000_000) == "2.3GB/s")
        // Values beyond GB stay in GB (last defined unit) rather than crashing.
        #expect(ByteRateFormatter.format(bytesPerSecond: 5_000_000_000_000) == "4656.6GB/s")
    }

    @Test func formatsExactUnitBoundary() {
        #expect(ByteRateFormatter.format(bytesPerSecond: 1024) == "1.0KB/s")
    }
}
