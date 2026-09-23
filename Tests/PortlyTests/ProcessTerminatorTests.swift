import Testing
import Foundation
@testable import PortlyCore

struct ProcessTerminatorTests {

    /// Spawned with only stdio inherited: a `Process` child would also inherit the
    /// test runner's other descriptors and, if a test failed to kill it, keep
    /// `swift test` waiting on them forever.
    private func spawn(_ script: String) throws -> pid_t {
        try Spawner.spawn(executable: "/bin/sh", arguments: ["-c", script])
    }

    /// A shell that ignores SIGTERM, returned only once the trap is installed -- a
    /// fixed delay raced the shell's startup on slow CI machines.
    private func spawnStubborn() async throws -> pid_t {
        let ready = FileManager.default.temporaryDirectory.appendingPathComponent("portly-ready-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: ready) }
        let pid = try spawn("trap '' TERM; : > '\(ready.path)'; while :; do sleep 0.1; done")
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: ready.path) {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        return pid
    }

    @Test func politeProcessesExitOnSIGTERM() async throws {
        let pid = try spawn("exec sleep 30")
        let outcome = await ProcessTerminator.terminate([pid], grace: 3)
        #expect(outcome == .terminated)
        #expect(!ProcessTerminator.isAlive(pid))
    }

    /// A process ignoring SIGTERM is SIGKILLed once the grace period runs out --
    /// the case that used to leave restart relaunching into a still-held port.
    @Test func stubbornProcessesAreEscalatedToSIGKILL() async throws {
        let pid = try await spawnStubborn()
        defer { kill(pid, SIGKILL) }
        let outcome = await ProcessTerminator.terminate([pid], grace: 0.5)
        #expect(outcome == .killed)
    }

    @Test func withoutEscalationAStubbornProcessSurvives() async throws {
        let pid = try await spawnStubborn()
        defer { kill(pid, SIGKILL) }
        let outcome = await ProcessTerminator.terminate([pid], grace: 0.3, escalate: false)
        #expect(outcome == .survived)
    }

    @Test func nonexistentPidsAreNotAlive() {
        #expect(!ProcessTerminator.isAlive(999_999))
    }
}
