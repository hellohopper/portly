import Testing
@testable import PortlyCore

struct ConnectionResolverTests {

    /// Real `lsof -iTCP:<port> -sTCP:ESTABLISHED -F pcn` output: one connection shows
    /// up twice, once from each end.
    private let sample = """
    p63629
    cPython
    f5
    n127.0.0.1:9310->127.0.0.1:56112
    p63875
    ccurl
    f3
    n127.0.0.1:56112->127.0.0.1:9310
    """

    @Test func collapsesBothHalvesOfOneConnection() {
        let peers = ConnectionResolver.parse(sample, port: 9310)
        #expect(peers.count == 1)
        #expect(peers[0].count == 1)
    }

    @Test func namesThePeerFromTheClientSideRow() {
        let peers = ConnectionResolver.parse(sample, port: 9310)
        #expect(peers[0].processName == "curl")
        #expect(peers[0].address == "127.0.0.1:56112")
    }

    @Test func formatsRepeatCountsInTheDisplayName() {
        let peer = ConnectionResolver.Peer(address: "127.0.0.1:1", processName: "Chrome", count: 3)
        #expect(peer.displayName == "Chrome ×3")

        let single = ConnectionResolver.Peer(address: "127.0.0.1:1", processName: "Chrome", count: 1)
        #expect(single.displayName == "Chrome")
    }

    @Test func fallsBackToTheAddressForUnnamedPeers() {
        let peer = ConnectionResolver.Peer(address: "192.168.1.9:5000", processName: nil, count: 1)
        #expect(peer.displayName == "192.168.1.9:5000")
    }

    @Test func ignoresRowsWithoutAPeer() {
        #expect(ConnectionResolver.parse("p1\ncfoo\nf3\nn127.0.0.1:9310\n", port: 9310).isEmpty)
        #expect(ConnectionResolver.parse("", port: 9310).isEmpty)
    }
}
