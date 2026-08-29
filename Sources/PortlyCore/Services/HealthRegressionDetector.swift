import Foundation

/// Decides which ports just crossed from healthy into 5xx, so the alert fires on the
/// transition rather than on every refresh while a server stays broken.
public enum HealthRegressionDetector {

    /// Ports (restricted to `pinned`) whose status went from non-failing to failing.
    /// A port with no previous reading is not a regression -- there is nothing to
    /// regress from, and alerting there would fire on every app launch.
    public static func regressions(
        old: [Int: Int],
        new: [Int: Int],
        pinned: Set<Int>
    ) -> [Int] {
        new.compactMap { port, newStatus in
            guard pinned.contains(port), let oldStatus = old[port] else { return nil }
            guard HealthChecker.Category.classify(statusCode: oldStatus) != .failing,
                  HealthChecker.Category.classify(statusCode: newStatus) == .failing else { return nil }
            return port
        }
        .sorted()
    }
}
