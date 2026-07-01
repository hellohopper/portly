import Foundation

struct PortInfo: Identifiable, Hashable {
    let pid: Int32
    let port: Int
    let proto: String        // "TCP" or "UDP"
    let processName: String
    let commandPath: String?
    var projectName: String?
    var gitBranch: String?
    var uptimeSeconds: Int?
    var cpuPercent: Double?
    var memPercent: Double?
    var frameworkLabel: String?

    var id: String { "\(pid)-\(port)-\(proto)" }
}
