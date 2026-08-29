import PortlyCore
import SwiftUI

struct HistoryView: View {
    @ObservedObject var history: HistoryStore
    /// Returns false when the recorded command couldn't be started again.
    let onRelaunch: (HistoryStore.Event) -> Bool

    @State private var failedRelaunch: HistoryStore.Event.ID?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Port History")
                    .font(.headline)
                Spacer()
                if !history.events.isEmpty {
                    Button("Clear") { history.clear() }
                }
            }

            if history.events.isEmpty {
                Text("No events yet — ports that start or stop listening will show up here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(history.events) { event in
                            HStack(spacing: 6) {
                                Image(systemName: Self.iconName(for: event.kind))
                                    .foregroundStyle(Self.iconColor(for: event.kind))
                                    .font(.caption)
                                Text(verbatim: "\(event.port)")
                                    .font(.system(.caption, design: .monospaced).bold())
                                Text(eventDescription(event))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                if event.isRelaunchable {
                                    Button(action: { relaunch(event) }) {
                                        Image(systemName: failedRelaunch == event.id
                                              ? "exclamationmark.triangle" : "play.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(failedRelaunch == event.id ? .orange : Color.accentColor)
                                    .help(failedRelaunch == event.id
                                          ? "Couldn't start it again"
                                          : "Start again: \(event.commandLine ?? "")")
                                }
                                Text(Self.relativeFormatter.localizedString(for: event.date, relativeTo: Date()))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    private func relaunch(_ event: HistoryStore.Event) {
        failedRelaunch = onRelaunch(event) ? nil : event.id
    }

    private static func iconName(for kind: HistoryStore.Event.Kind) -> String {
        switch kind {
        case .opened: return "arrow.up.circle.fill"
        case .closed: return "arrow.down.circle.fill"
        case .replaced: return "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    private static func iconColor(for kind: HistoryStore.Event.Kind) -> Color {
        switch kind {
        case .opened: return .green
        case .closed: return .secondary
        case .replaced: return .orange
        }
    }

    private func eventDescription(_ event: HistoryStore.Event) -> String {
        var parts = [event.processName, event.kind.rawValue]
        if let projectName = event.projectName {
            parts.insert(projectName, at: 1)
        }
        return parts.joined(separator: " · ")
    }
}
