import Testing
@testable import PortlyCore

struct DockerContainerResolverTests {

    @Test func parsesNamesAgainstEachForwardedPort() {
        let output = "myapp-web-1\t0.0.0.0:3000->3000/tcp, :::3000->3000/tcp\n" +
                     "myapp-db-1\t0.0.0.0:5432->5432/tcp"
        let result = DockerContainerResolver.parse(output)
        #expect(result[3000] == "myapp-web-1")
        #expect(result[5432] == "myapp-db-1")
    }

    @Test func ignoresContainersWithNoPublishedPorts() {
        let output = "myapp-worker-1\t"
        #expect(DockerContainerResolver.parse(output).isEmpty)
    }

    @Test func ignoresMalformedLines() {
        #expect(DockerContainerResolver.parse("not a valid line").isEmpty)
        #expect(DockerContainerResolver.parse("").isEmpty)
    }
}
