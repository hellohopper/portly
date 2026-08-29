import Foundation

/// Pure focus-movement logic for arrow-key navigation through the visible port
/// list, kept separate from the NSEvent plumbing so it can be unit tested.
public enum KeyboardNavigator {
    public enum Direction: Sendable {
        case down
        case up
    }

    /// Returns the row that should be focused after moving from `current`.
    /// No focus yet: ↓ starts at the top, ↑ starts at the bottom. Movement clamps
    /// at the ends rather than wrapping. A focused row that vanished (killed,
    /// filtered out) restarts as if nothing was focused.
    ///
    /// Generic over the row identifier because two processes can listen on the same
    /// port number (on different local addresses), so a port number does not identify
    /// a row -- moving and acting have to work in terms of `PortInfo.id`.
    public static func move<ID: Equatable>(from current: ID?, in visibleRows: [ID], direction: Direction) -> ID? {
        guard !visibleRows.isEmpty else { return nil }
        guard let current, let index = visibleRows.firstIndex(of: current) else {
            return direction == .down ? visibleRows.first : visibleRows.last
        }

        switch direction {
        case .down:
            return visibleRows[min(index + 1, visibleRows.count - 1)]
        case .up:
            return visibleRows[max(index - 1, 0)]
        }
    }
}
