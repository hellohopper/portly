import Foundation

struct PortInfo: Identifiable, Hashable {
    let pid: Int32
    let port: Int
    var proto: String        // "TCP", "UDP", or "TCP+UDP" once merged
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
