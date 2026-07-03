import Testing
@testable import PortlyCore

struct DockerDetectorTests {

    @Test func detectsDockerBackend() {
        #expect(DockerDetector.isDockerManaged(processName: "com.docker.backend"))
    }

    @Test func detectsDockerProxy() {
        #expect(DockerDetector.isDockerManaged(processName: "docker-proxy"))
    }

    @Test func doesNotFlagRegularProcesses() {
        #expect(!DockerDetector.isDockerManaged(processName: "node"))
        #expect(!DockerDetector.isDockerManaged(processName: "python3"))
    }

    @Test func portInfoExposesIsDockerManaged() {
        let dockerPort = PortInfo(pid: 1, port: 8080, proto: "TCP", processName: "com.docker.backend", commandPath: nil)
        let regularPort = PortInfo(pid: 2, port: 3000, proto: "TCP", processName: "node", commandPath: nil)

        #expect(dockerPort.isDockerManaged)
        #expect(!regularPort.isDockerManaged)
    }

    @Test func searchMatchesDockerKeyword() {
        let dockerPort = PortInfo(pid: 1, port: 8080, proto: "TCP", processName: "com.docker.backend", commandPath: nil)
        #expect(dockerPort.matches(query: "docker"))
    }
}
