import Foundation

public enum ProcessMetricsResolver {

    public struct Metrics: Sendable {
        public let cpuPercent: Double
        public let memPercent: Double
    }

    /// Energy Impact-style classification based on CPU usage, mirroring the color coding
    /// used by Activity Monitor's Energy tab (macOS doesn't expose the actual private score).
    public enum EnergyLevel: Sendable {
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
