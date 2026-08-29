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

    @Test func expandsPublishedPortRanges() {
        let result = DockerContainerResolver.parse("api\t0.0.0.0:8000-8002->8000-8002/tcp")
        #expect(result[8000] == "api")
        #expect(result[8001] == "api")
        #expect(result[8002] == "api")
    }

    @Test func portRangeHelperHandlesEdgeCases() {
        #expect(DockerContainerResolver.expandPorts("8000") == [8000])
        #expect(DockerContainerResolver.expandPorts("8000-8002") == [8000, 8001, 8002])
        #expect(DockerContainerResolver.expandPorts("8002-8000").isEmpty)
        #expect(DockerContainerResolver.expandPorts("nonsense").isEmpty)
        // Guard against a pathological range trying to allocate 65k entries.
        #expect(DockerContainerResolver.expandPorts("1-65535").isEmpty)
    }
}
