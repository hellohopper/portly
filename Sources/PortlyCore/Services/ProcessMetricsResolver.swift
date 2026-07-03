import Foundation

public enum ProcessMetricsResolver {

    public struct Metrics {
        public let cpuPercent: Double
        public let memPercent: Double
    }

    /// Batch-resolves %CPU and %MEM for the given pids using a single `ps` call.
    public static func metrics(for pids: [Int32]) -> [Int32: Metrics] {
        guard !pids.isEmpty else { return [:] }

        let pidList = pids.map(String.init).joined(separator: ",")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "pid=,pcpu=,pmem=", "-p", pidList]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var result: [Int32: Metrics] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
            guard parts.count >= 3,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let mem = Double(parts[2]) else { continue }
            result[pid] = Metrics(cpuPercent: cpu, memPercent: mem)
        }
        return result
    }

    /// Energy Impact-style classification based on CPU usage, mirroring the color coding
    /// used by Activity Monitor's Energy tab (macOS doesn't expose the actual private score).
    public enum EnergyLevel {
        case low, medium, high

        public static func from(cpuPercent: Double) -> EnergyLevel {
            switch cpuPercent {
            case ..<5: return .low
            case 5..<20: return .medium
            default: return .high
            }
        }
    }
}
