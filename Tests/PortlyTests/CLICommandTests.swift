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

    @Test func parsesWatch() {
        #expect(CLICommand.parse(["watch"]) == .watch)
    }

    @Test func rejectsWatchWithExtraArguments() {
        #expect(CLICommand.parse(["watch", "--json"]) == nil)
    }

    @Test func parsesWaitWithAndWithoutTimeout() {
        #expect(CLICommand.parse(["wait", "3000"]) == .wait(port: 3000, timeout: CLICommand.defaultWaitTimeout))
        #expect(CLICommand.parse(["wait", "3000", "--timeout", "5"]) == .wait(port: 3000, timeout: 5))
    }

    @Test func rejectsMalformedWait() {
        #expect(CLICommand.parse(["wait"]) == nil)
        #expect(CLICommand.parse(["wait", "abc"]) == nil)
        #expect(CLICommand.parse(["wait", "70000"]) == nil)
        #expect(CLICommand.parse(["wait", "3000", "--timeout"]) == nil)
        #expect(CLICommand.parse(["wait", "3000", "--timeout", "0"]) == nil)
        #expect(CLICommand.parse(["wait", "3000", "--wat", "5"]) == nil)
    }

    @Test func parsesFree() {
        #expect(CLICommand.parse(["free"]) == .free)
        #expect(CLICommand.parse(["free", "extra"]) == nil)
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

    @Test func parsesRunWithAndWithoutExplicitPort() {
        #expect(CLICommand.parse(["run", "--", "npm", "run", "dev"]) == .run(port: nil, command: ["npm", "run", "dev"]))
        #expect(CLICommand.parse(["run", "--port", "4000", "--", "node", "server.js"])
                == .run(port: 4000, command: ["node", "server.js"]))
    }

    @Test func rejectsMalformedRun() {
        #expect(CLICommand.parse(["run"]) == nil)
        #expect(CLICommand.parse(["run", "npm", "run", "dev"]) == nil) // missing "--"
        #expect(CLICommand.parse(["run", "--"]) == nil) // empty command
        #expect(CLICommand.parse(["run", "--port", "abc", "--", "node"]) == nil)
        #expect(CLICommand.parse(["run", "--port", "70000", "--", "node"]) == nil)
    }

    @Test func parsesCompletions() {
        #expect(CLICommand.parse(["completions", "zsh"]) == .completions(.zsh))
        #expect(CLICommand.parse(["completions", "fish"]) == .completions(.fish))
    }

    @Test func rejectsUnknownShellForCompletions() {
        #expect(CLICommand.parse(["completions", "bash"]) == nil)
        #expect(CLICommand.parse(["completions"]) == nil)
    }
}
