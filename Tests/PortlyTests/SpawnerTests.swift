import Testing
import Foundation
@testable import PortlyCore

struct SpawnerTests {

    /// The bug this exists for: `Process` children inherited every stray descriptor,
    /// so one helper could hold another's pipe open and starve its reader.
    @Test func childrenInheritOnlyStdio() throws {
        var stray: [Int32] = [0, 0]
        #expect(pipe(&stray) == 0) // deliberately *not* close-on-exec
        defer { close(stray[0]); close(stray[1]) }

        let script = "for fd in \(stray[0]) \(stray[1]); do [ -e /dev/fd/$fd ] && echo leaked $fd; done; echo checked"
        let output = Shell.run("/bin/sh", ["-c", script])?.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(output == "checked")
    }

    @Test func reportsExitStatusAndSignals() throws {
        let exited = try Spawner.spawn(executable: "/bin/sh", arguments: ["-c", "exit 3"], reap: false)
        #expect(Spawner.wait(for: exited) == 3)

        let killed = try Spawner.spawn(executable: "/bin/sh", arguments: ["-c", "kill -9 $$"], reap: false)
        #expect(Spawner.wait(for: killed) == 128 + SIGKILL)
    }

    @Test func honoursWorkingDirectoryAndEnvironment() {
        let output = Shell.run("/bin/sh", ["-c", "pwd"])
        #expect(output != nil)

        guard let pipe = Spawner.makePipe() else { Issue.record("pipe failed"); return }
        let pid = try? Spawner.spawn(
            executable: "/bin/sh", arguments: ["-c", "echo \"$(pwd) $PORTLY_TEST\""],
            environment: ["PORTLY_TEST": "hello", "PATH": "/usr/bin:/bin"],
            workingDirectory: "/usr",
            stdout: pipe.write, reap: false
        )
        close(pipe.write)
        let data = FileHandle(fileDescriptor: pipe.read, closeOnDealloc: true).readDataToEndOfFile()
        if let pid { _ = Spawner.wait(for: pid) }
        #expect(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "/usr hello")
    }

    @Test func failsForAMissingExecutable() {
        #expect(throws: Spawner.SpawnError.self) {
            try Spawner.spawn(executable: "/nonexistent/binary", arguments: [])
        }
    }
}
