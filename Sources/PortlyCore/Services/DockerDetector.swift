import Foundation

enum DockerDetector {

    /// Docker Desktop on macOS forwards published container ports through its own
    /// virtualization process (typically "com.docker.backend", historically
    /// "docker-proxy" or "com.docker.vpnkit-bridge") rather than the containerized
    /// service showing up directly in `lsof` -- this flags those host-side listeners.
    private static let dockerProcessSignatures = [
        "com.docker.backend",
        "docker-proxy",
        "com.docker.vpnkit",
        "com.docker.hyperkit"
    ]

    static func isDockerManaged(processName: String) -> Bool {
        let name = processName.lowercased()
        return dockerProcessSignatures.contains { name.contains($0.lowercased()) }
    }
}
