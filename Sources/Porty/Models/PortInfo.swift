import Foundation

struct PortInfo: Identifiable, Hashable {
    let pid: Int32
    let port: Int
    let proto: String        // "TCP" or "UDP"
    let processName: String
    let commandPath: String?

    var id: String { "\(pid)-\(port)-\(proto)" }
}
