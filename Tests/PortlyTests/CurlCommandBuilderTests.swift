import Testing
@testable import Portly

struct CurlCommandBuilderTests {

    @Test func buildsRunnableCurlCommand() {
        #expect(CurlCommandBuilder.command(port: 3000) == "curl -i http://localhost:3000/")
    }

    @Test func portIsNotLocaleFormatted() {
        // Regression guard for the class of bug where 8765 rendered as "8,765".
        #expect(CurlCommandBuilder.command(port: 8765).contains("localhost:8765/"))
    }
}
