import Testing
@testable import PortlyCore

struct ProcessTableTests {

    @Test func parsesAllColumns() {
        let output = "  501     1       03:20  12.5  1.8 /usr/local/bin/node"
        let table = ProcessTable.parse(output)
        let entry = table[501]
        #expect(entry?.ppid == 1)
        #expect(entry?.name == "node")
        #expect(entry?.uptimeSeconds == 200)
        #expect(entry?.cpuPercent == 12.5)
        #expect(entry?.memPercent == 1.8)
    }

    @Test func keepsPathsContainingSpaces() {
        let output = "700 1 01:00 0.0 0.0 /Applications/My App.app/Contents/MacOS/My App"
        #expect(ProcessTable.parse(output)[700]?.name == "My App")
    }

    @Test func skipsMalformedLines() {
        #expect(ProcessTable.parse("garbage").isEmpty)
        #expect(ProcessTable.parse("").isEmpty)
    }

    @Test func derivesAStableStartTimeFromElapsedTime() {
        let table = ProcessTable(
            entries: [42: .init(ppid: 1, name: "node", uptimeSeconds: 100, cpuPercent: 0, memPercent: 0)],
            takenAtSystemUptime: 1000
        )
        #expect(table.startTime(of: 42) == 900)
    }

    @Test func exposesPerPidViews() {
        let table = ProcessTable(
            entries: [
                1: .init(ppid: 0, name: "launchd", uptimeSeconds: 500, cpuPercent: 1, memPercent: 2),
                9: .init(ppid: 1, name: "node", uptimeSeconds: 60, cpuPercent: 3, memPercent: 4)
            ],
            takenAtSystemUptime: 1000
        )
        #expect(table.uptimeSeconds(for: [9]) == [9: 60])
        #expect(table.metrics(for: [9])[9]?.cpuPercent == 3)
        #expect(table.ancestryTable[9]?.name == "node")
    }
}
