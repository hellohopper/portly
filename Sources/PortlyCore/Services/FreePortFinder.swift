import Foundation

/// Suggests an unused port from the ranges dev servers commonly default to, so
/// starting a new project doesn't mean guessing numbers until one doesn't collide.
public enum FreePortFinder {
    public static let commonRanges: [ClosedRange<Int>] = [3000...3999, 5000...5999, 8000...8999]

    public static func suggest(excluding usedPorts: Set<Int>, ranges: [ClosedRange<Int>] = commonRanges) -> Int? {
        for range in ranges {
            for port in range where !usedPorts.contains(port) {
                return port
            }
        }
        return nil
    }
}
