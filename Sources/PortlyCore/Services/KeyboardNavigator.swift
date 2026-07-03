import Foundation

/// Pure focus-movement logic for arrow-key navigation through the visible port
/// list, kept separate from the NSEvent plumbing so it can be unit tested.
public enum KeyboardNavigator {
    public enum Direction: Sendable {
        case down
        case up
    }

    /// Returns the port that should be focused after moving from `current`.
    /// No focus yet: ↓ starts at the top, ↑ starts at the bottom. Movement clamps
    /// at the ends rather than wrapping. A focused port that vanished (killed,
    /// filtered out) restarts as if nothing was focused.
    public static func move(from current: Int?, in visiblePorts: [Int], direction: Direction) -> Int? {
        guard !visiblePorts.isEmpty else { return nil }
        guard let current, let index = visiblePorts.firstIndex(of: current) else {
            return direction == .down ? visiblePorts.first : visiblePorts.last
        }

        switch direction {
        case .down:
            return visiblePorts[min(index + 1, visiblePorts.count - 1)]
        case .up:
            return visiblePorts[max(index - 1, 0)]
        }
    }
}
