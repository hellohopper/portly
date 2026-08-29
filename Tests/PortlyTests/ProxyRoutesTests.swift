import Testing
@testable import PortlyCore

struct ProxyRoutesTests {

    private func info(port: Int, proto: String = "TCP") -> PortInfo {
        PortInfo(pid: 1, port: port, proto: proto, processName: "node", commandPath: nil)
    }

    @Test func mapsNamesToLiveTCPPorts() {
        let routes = LocalhostProxyServer.routes(
            names: [3000: "web"], livePorts: [info(port: 3000)]
        )
        #expect(routes == ["web": 3000])
    }

    /// The whole point of rebuilding the table each scan: a name whose port died must
    /// stop resolving, rather than dead-ending or shadowing a new claimant.
    @Test func dropsNamesWhosePortIsGone() {
        let routes = LocalhostProxyServer.routes(names: [3000: "web"], livePorts: [])
        #expect(routes.isEmpty)
    }

    @Test func ignoresUDPOnlyPorts() {
        let routes = LocalhostProxyServer.routes(
            names: [5353: "mdns"], livePorts: [info(port: 5353, proto: "UDP")]
        )
        #expect(routes.isEmpty)
    }

    @Test func acceptsMergedTCPUDPRows() {
        let routes = LocalhostProxyServer.routes(
            names: [17500: "dropbox"], livePorts: [info(port: 17500, proto: "TCP+UDP")]
        )
        #expect(routes == ["dropbox": 17500])
    }

    @Test func keepsOnlyMappingsForListedPorts() {
        let routes = LocalhostProxyServer.routes(
            names: [3000: "web", 8080: "api"],
            livePorts: [info(port: 3000)]
        )
        #expect(routes == ["web": 3000])
    }
}
