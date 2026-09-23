import Testing
import Foundation
@testable import PortlyCore

struct PortEnricherTests {

    private func makeRepo(branch: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortlyEnricherTests-\(UUID().uuidString)")
        let gitDir = root.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/\(branch)\n".write(
            to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8
        )
        return root
    }

    /// `git checkout` under a running dev server used to go unnoticed: the whole
    /// context, branch included, was cached for the life of the process.
    @Test func cachedContextPicksUpBranchSwitches() throws {
        let repo = try makeRepo(branch: "main")
        defer { try? FileManager.default.removeItem(at: repo) }

        var cache: [Int32: PortEnricher.ProjectContext] = [
            42: PortEnricher.ProjectContext(
                projectName: "repo", gitBranch: "main", workingDirectory: repo.path,
                startTime: 100, gitDirectory: repo.appendingPathComponent(".git").path
            )
        ]
        try "ref: refs/heads/feature\n".write(
            to: repo.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8
        )

        let context = PortEnricher.projectContext(for: 42, startedAt: 100, cache: &cache)
        #expect(context.gitBranch == "feature")
        #expect(cache[42]?.gitBranch == "feature")
        #expect(context.projectName == "repo")
    }

    /// Dead pids are dropped from the cache instead of accumulating forever, and the
    /// command line is remembered for the next refresh.
    @Test func enrichPrunesDeadPidsAndCachesCommandLines() async {
        let pid = ProcessInfo.processInfo.processIdentifier
        let scanned = [PortInfo(pid: pid, port: 65_000, proto: "TCP", processName: "test", commandPath: nil)]
        let stale = PortEnricher.ProjectContext(
            projectName: nil, gitBranch: nil, workingDirectory: nil, startTime: nil
        )

        let result = await PortEnricher.enrich(
            scanned,
            options: PortEnricher.Options(includeThroughput: false, includeAncestry: false, includeDockerNames: false),
            contextCache: [999_999: stale]
        )

        #expect(result.contextCache[999_999] == nil)
        #expect(result.contextCache[pid]?.commandLine?.isEmpty == false)
        #expect(result.ports.first?.commandLine == result.contextCache[pid]?.commandLine)
    }
}
