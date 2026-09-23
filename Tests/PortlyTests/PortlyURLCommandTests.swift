import Testing
import Foundation
@testable import PortlyCore

struct PortlyURLCommandTests {

    private func parse(_ string: String) -> PortlyURLCommand? {
        URL(string: string).flatMap(PortlyURLCommand.parse)
    }

    @Test func parsesPathAndQueryForms() {
        #expect(parse("portly://open/3000") == .open(port: 3000))
        #expect(parse("portly://kill?port=8080") == .kill(port: 8080))
        #expect(parse("portly://force-kill/5173") == .forceKill(port: 5173))
        #expect(parse("portly://restart/3000") == .restart(port: 3000))
        #expect(parse("portly://pin/3000") == .pin(port: 3000))
        #expect(parse("portly://unpin/3000") == .unpin(port: 3000))
        #expect(parse("portly://copy/3000") == .copy(port: 3000))
    }

    @Test func showTakesAnOptionalSearch() {
        #expect(parse("portly://show") == .show(search: nil))
        #expect(parse("portly://show?search=vite") == .show(search: "vite"))
        #expect(parse("portly://") == .show(search: nil))
    }

    @Test func rejectsBadInput() {
        #expect(parse("https://open/3000") == nil)
        #expect(parse("portly://open") == nil)
        #expect(parse("portly://open/99999") == nil)
        #expect(parse("portly://explode/3000") == nil)
    }

    @Test func onlyKillAndRestartAreDestructive() {
        #expect(PortlyURLCommand.kill(port: 1).isDestructive)
        #expect(PortlyURLCommand.forceKill(port: 1).isDestructive)
        #expect(PortlyURLCommand.restart(port: 1).isDestructive)
        #expect(!PortlyURLCommand.open(port: 1).isDestructive)
        #expect(!PortlyURLCommand.pin(port: 1).isDestructive)
    }
}
