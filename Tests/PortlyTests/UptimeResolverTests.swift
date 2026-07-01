import Testing
@testable import Portly

struct UptimeResolverTests {

    @Test func parseElapsedMinutesSeconds() {
        #expect(UptimeResolver.parseElapsed("02:30") == 150)
    }

    @Test func parseElapsedHoursMinutesSeconds() {
        #expect(UptimeResolver.parseElapsed("01:02:03") == 3723)
    }

    @Test func parseElapsedDaysHoursMinutesSeconds() {
        #expect(UptimeResolver.parseElapsed("3-01:02:03") == 3 * 86400 + 3723)
    }

    @Test func parseElapsedReturnsNilForGarbage() {
        #expect(UptimeResolver.parseElapsed("not-a-time") == nil)
    }

    @Test func formatUnderAMinute() {
        #expect(UptimeResolver.format(45) == "45s")
    }

    @Test func formatMinutesOnly() {
        #expect(UptimeResolver.format(150) == "2m")
    }

    @Test func formatHoursAndMinutes() {
        #expect(UptimeResolver.format(3723) == "1h 2m")
    }

    @Test func formatDaysAndHours() {
        #expect(UptimeResolver.format(3 * 86400 + 3600) == "3d 1h")
    }
}
