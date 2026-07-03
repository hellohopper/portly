import Foundation

public enum ByteRateFormatter {
    /// Formats a bytes/sec value as a short human-readable rate, e.g. "482B/s", "12KB/s", "3.4MB/s".
    public static func format(bytesPerSecond: Double) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = bytesPerSecond
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        let formatted = unitIndex == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(formatted)\(units[unitIndex])/s"
    }
}
