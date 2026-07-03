import Testing
@testable import PortlyCLI

struct CLICommandTests {

    @Test func noArgumentsDefaultsToList() {
        #expect(CLICommand.parse([]) == .list(json: false))
    }

    @Test func parsesListAndJSONFlag() {
        #expect(CLICommand.parse(["list"]) == .list(json: false))
        #expect(CLICommand.parse(["list", "--json"]) == .list(json: true))
    }

    @Test func rejectsUnknownListFlags() {
        #expect(CLICommand.parse(["list", "--verbose"]) == nil)
    }

    @Test func parsesKillWithValidPort() {
        #expect(CLICommand.parse(["kill", "3000"]) == .kill(port: 3000))
    }

    @Test func rejectsMalformedKill() {
        #expect(CLICommand.parse(["kill"]) == nil)
        #expect(CLICommand.parse(["kill", "abc"]) == nil)
        #expect(CLICommand.parse(["kill", "0"]) == nil)
        #expect(CLICommand.parse(["kill", "70000"]) == nil)
        #expect(CLICommand.parse(["kill", "3000", "extra"]) == nil)
    }

    @Test func parsesVersionAndHelpAliases() {
        #expect(CLICommand.parse(["version"]) == .version)
        #expect(CLICommand.parse(["--version"]) == .version)
        #expect(CLICommand.parse(["-v"]) == .version)
        #expect(CLICommand.parse(["help"]) == .help)
        #expect(CLICommand.parse(["--help"]) == .help)
        #expect(CLICommand.parse(["-h"]) == .help)
    }

    @Test func rejectsUnknownCommand() {
        #expect(CLICommand.parse(["frobnicate"]) == nil)
    }
}
