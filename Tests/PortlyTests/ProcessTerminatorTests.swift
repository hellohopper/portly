import Testing
import Foundation
@testable import PortlyCore

struct ProcessTerminatorTests {

    private func spawn(_ script: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
        return process
    }

    @Test func politeProcessesExitOnSIGTERM() async throws {
        let process = try spawn("exec sleep 30")
        let outcome = await ProcessTerminator.terminate([process.processIdentifier], grace: 3)
        #expect(outcome == .terminated)
        #expect(!ProcessTerminator.isAlive(process.processIdentifier))
    }

    /// A process ignoring SIGTERM is SIGKILLed once the grace period runs out --
    /// the case that used to leave restart relaunching into a still-held port.
    @Test func stubbornProcessesAreEscalatedToSIGKILL() async throws {
        let process = try spawn("trap '' TERM; while :; do sleep 0.1; done")
        try await Task.sleep(nanoseconds: 200_000_000) // let the trap install
        let outcome = await ProcessTerminator.terminate([process.processIdentifier], grace: 0.5)
        #expect(outcome == .killed)
    }

    @Test func withoutEscalationAStubbornProcessSurvives() async throws {
        let process = try spawn("trap '' TERM; while :; do sleep 0.1; done")
        defer { kill(process.processIdentifier, SIGKILL) }
        try await Task.sleep(nanoseconds: 200_000_000)
        let outcome = await ProcessTerminator.terminate([process.processIdentifier], grace: 0.3, escalate: false)
        #expect(outcome == .survived)
    }

    @Test func nonexistentPidsAreNotAlive() {
        #expect(!ProcessTerminator.isAlive(999_999))
    }
}
