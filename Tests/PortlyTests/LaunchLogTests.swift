import Testing
import Foundation
@testable import PortlyCore

struct LaunchLogTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PortlyLaunchLog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func namesAreFilesystemSafe() {
        #expect(LaunchLog.name("my app", "3000") == "my-app-3000")
        #expect(LaunchLog.name("a/b:c", nil, "web") == "a-b-c-web")
        #expect(LaunchLog.name("", nil) == "process")
    }

    @Test func appendsARunHeaderEachLaunch() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        for run in 1...2 {
            let handle = try #require(LaunchLog.open(name: "web", commandLine: "npm run dev", workingDirectory: "/tmp", in: dir))
            try handle.write(contentsOf: Data("output \(run)\n".utf8))
            try handle.close()
        }
        let text = try String(contentsOf: LaunchLog.url(for: "web", in: dir), encoding: .utf8)
        #expect(text.components(separatedBy: "=== ").count == 3)
        #expect(text.contains("npm run dev (in /tmp)"))
        #expect(text.contains("output 1") && text.contains("output 2"))
    }

    @Test func tailReturnsTheLastLinesOnly() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("big.log")
        try (1...500).map { "line \($0)" }.joined(separator: "\n").appending("\n")
            .write(to: file, atomically: true, encoding: .utf8)

        #expect(LaunchLog.tail(of: file.path, maxLines: 3) == ["line 498", "line 499", "line 500"])
        // Reading only the last few bytes drops the partial first line.
        #expect(LaunchLog.tail(of: file.path, maxLines: 100, maxBytes: 20) == ["line 499", "line 500"])
        #expect(LaunchLog.tail(of: dir.appendingPathComponent("missing").path).isEmpty)
    }

    /// End to end: a launched command's output lands in its log.
    @Test func launcherRedirectsOutputToTheLog() async throws {
        let name = "portly-test-\(UUID().uuidString)"
        let url = LaunchLog.url(for: name)
        defer { try? FileManager.default.removeItem(at: url) }

        let pid = try #require(ProcessLauncher.launchProcess(
            commandLine: "/bin/echo hello-from-child", workingDirectory: nil, logName: name
        ))
        #expect(await ProcessTerminator.waitForExit([pid], timeout: 5))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("hello-from-child"))
    }
}
