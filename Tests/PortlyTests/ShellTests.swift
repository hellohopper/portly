import Testing
import Foundation
@testable import PortlyCore

struct ShellTests {

    @Test func capturesStdout() {
        #expect(Shell.run("/bin/echo", ["hello"])?.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
    }

    @Test func returnsNilForAMissingExecutable() {
        #expect(Shell.run("/nonexistent/binary", []) == nil)
    }

    /// The deadlock this helper exists to prevent: a child that writes more than the
    /// pipe buffer to stderr blocks forever if only stdout is drained.
    @Test func doesNotDeadlockOnLargeStderrOutput() {
        let script = "for i in $(seq 1 20000); do echo 'warning: some noisy diagnostic line' >&2; done; echo done"
        let output = Shell.run("/bin/sh", ["-c", script], timeout: 20)
        #expect(output?.trimmingCharacters(in: .whitespacesAndNewlines) == "done")
    }

    @Test func timesOutRatherThanHangingForever() {
        let start = Date()
        let output = Shell.run("/bin/sh", ["-c", "sleep 30"], timeout: 1)
        #expect(output == nil)
        #expect(Date().timeIntervalSince(start) < 10)
    }
}
