import Testing
@testable import Portly

struct ProcessTreeResolverTests {

    // Simulated ps table: Terminal(10) > zsh(20) > npm(30) > node(40)
    private let table: [Int32: (ppid: Int32, name: String)] = [
        10: (1, "Terminal"),
        20: (10, "zsh"),
        30: (20, "npm"),
        40: (30, "node")
    ]

    @Test func parsesPsOutputWithSpacesInCommandPath() {
        let output = """
            1     0 /sbin/launchd
          538     1 /System/Library/Frameworks/FSEvents.framework/Versions/A/Support/fseventsd
         4821  4788 /Users/dev/My Projects/bin/node
        """
        let parsed = ProcessTreeResolver.parseTable(output)
        #expect(parsed[1]?.name == "launchd")
        #expect(parsed[538]?.name == "fseventsd")
        #expect(parsed[4821]?.ppid == 4788)
        #expect(parsed[4821]?.name == "node")
    }

    @Test func ancestryStopsAtShellBoundary() {
        let chain = ProcessTreeResolver.ancestry(of: 40, in: table)
        // node's ancestry is just npm -- the zsh above it is a boundary.
        #expect(chain.map(\.name) == ["npm"])
        #expect(chain.map(\.pid) == [30])
    }

    @Test func ancestryIsEmptyWhenParentIsBoundary() {
        let chain = ProcessTreeResolver.ancestry(of: 30, in: table)
        #expect(chain.isEmpty)
    }

    @Test func ancestryIsEmptyForUnknownPid() {
        #expect(ProcessTreeResolver.ancestry(of: 999, in: table).isEmpty)
    }

    @Test func ancestrySurvivesCycles() {
        // Corrupt table where 50 and 60 point at each other must not loop forever.
        let cyclic: [Int32: (ppid: Int32, name: String)] = [
            50: (60, "a"),
            60: (50, "b")
        ]
        let chain = ProcessTreeResolver.ancestry(of: 50, in: cyclic)
        #expect(chain.map(\.name) == ["b"])
    }

    @Test func describeReadsOutermostFirst() {
        let chain = ProcessTreeResolver.ancestry(of: 40, in: table)
        #expect(ProcessTreeResolver.describe(leafName: "node", ancestry: chain) == "npm → node")
    }

    @Test func deepChainIsCapped() {
        var deep: [Int32: (ppid: Int32, name: String)] = [:]
        for i: Int32 in 2...20 {
            deep[i] = (i - 1, "p\(i - 1)")
        }
        deep[1] = (0, "p0")
        #expect(ProcessTreeResolver.ancestry(of: 20, in: deep).count == 6)
    }
}
