import Testing
@testable import Portly

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
}
