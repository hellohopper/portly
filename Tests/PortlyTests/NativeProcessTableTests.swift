import Testing
import Foundation
@testable import PortlyCore

struct NativeProcessTableTests {

    @Test func readsThisProcessFromTheKernel() throws {
        let table = try #require(NativeProcessTable.snapshot())
        let me = ProcessInfo.processInfo.processIdentifier
        let entry = try #require(table.entries[me])
        #expect(entry.ppid == getppid())
        #expect((entry.residentBytes ?? 0) > 0)
        #expect(entry.startTime != nil)
        #expect(table.startTime(of: me) == entry.startTime)
    }

    /// %CPU comes from the change in cumulative CPU time between two snapshots.
    @Test func cpuPercentIsTheDeltaOverWallTime() {
        let sampler = CPUSampler()
        let t0 = Date(timeIntervalSince1970: 1000)
        #expect(sampler.percentages(for: [7: (start: 1, nanoseconds: 1_000_000_000)], at: t0).isEmpty)
        // 0.5s of CPU over 2s of wall time = 25%.
        let result = sampler.percentages(for: [7: (start: 1, nanoseconds: 1_500_000_000)], at: t0.addingTimeInterval(2))
        #expect(abs((result[7] ?? 0) - 25) < 0.001)
    }

    /// A reused pid (different start time) starts over instead of yielding garbage.
    @Test func reusedPidsStartFresh() {
        let sampler = CPUSampler()
        let t0 = Date(timeIntervalSince1970: 1000)
        _ = sampler.percentages(for: [7: (start: 1, nanoseconds: 9_000_000_000)], at: t0)
        let result = sampler.percentages(for: [7: (start: 2, nanoseconds: 100)], at: t0.addingTimeInterval(2))
        #expect(result[7] == nil)
    }

    @Test func parsesKernelArgumentBuffers() {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: Int32(3)) { bytes.append(contentsOf: $0) }
        bytes += Array("/opt/homebrew/bin/node".utf8) + [0, 0, 0, 0]
        bytes += Array("node".utf8) + [0] + Array("server.js".utf8) + [0] + Array("--port".utf8) + [0]
        bytes += Array("PATH=/usr/bin".utf8) + [0]
        #expect(ProcessArguments.parse(bytes) == ["node", "server.js", "--port"])
        #expect(ProcessArguments.parse([1, 0]) == nil)
    }

    @Test func readsOwnArgumentsAndDisplayName() throws {
        let me = ProcessInfo.processInfo.processIdentifier
        let argv = try #require(ProcessArguments.argv(of: me))
        #expect(argv.first == CommandLine.arguments.first)
        #expect(ProcessArguments.displayName(of: me) == (CommandLine.arguments[0] as NSString).lastPathComponent)
    }
}
