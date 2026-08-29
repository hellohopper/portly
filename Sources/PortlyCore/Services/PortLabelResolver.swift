import Foundation

/// The two label rules the UI depends on, in one testable place: which label wins,
/// and what the search field matches against.
public enum PortLabelResolver {

    /// A user's manually-set label always beats the one a project's `.portly.json`
    /// contributed -- the file is a team default, the manual label is this machine's
    /// deliberate override.
    public static func effectiveLabel(
        for port: Int,
        manual: [Int: String],
        fromConfig: [Int: String]
    ) -> String? {
        manual[port] ?? fromConfig[port]
    }

    /// Whether a row matches the search field. Labels live keyed by port rather than
    /// on `PortInfo`, so they need this extra check to be searchable at all.
    ///
    /// `needle` is expected already trimmed and lowercased -- normalising it once per
    /// filter pass rather than once per row.
    public static func matches(
        _ info: PortInfo,
        needle: String,
        manual: [Int: String],
        fromConfig: [Int: String]
    ) -> Bool {
        guard !needle.isEmpty else { return true }
        if info.matches(query: needle) { return true }
        guard let label = effectiveLabel(for: info.port, manual: manual, fromConfig: fromConfig) else {
            return false
        }
        return label.lowercased().contains(needle)
    }
}
