import Testing
@testable import PortlyCore

struct HealthCheckerTests {

    @Test func successAndRedirectCodesAreHealthy() {
        #expect(HealthChecker.Category.classify(statusCode: 200) == .healthy)
        #expect(HealthChecker.Category.classify(statusCode: 204) == .healthy)
        #expect(HealthChecker.Category.classify(statusCode: 301) == .healthy)
        #expect(HealthChecker.Category.classify(statusCode: 304) == .healthy)
    }

    @Test func clientErrorsAreWarnings() {
        // A 404 on "/" still means the server is up and responding.
        #expect(HealthChecker.Category.classify(statusCode: 404) == .warning)
        #expect(HealthChecker.Category.classify(statusCode: 401) == .warning)
    }

    @Test func serverErrorsAreFailing() {
        #expect(HealthChecker.Category.classify(statusCode: 500) == .failing)
        #expect(HealthChecker.Category.classify(statusCode: 503) == .failing)
    }
}
