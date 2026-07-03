import SwiftUI

struct HistoryView: View {
    @ObservedObject var history: HistoryStore

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
                                Image(systemName: event.kind == .opened ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                    .foregroundStyle(event.kind == .opened ? .green : .secondary)
                                    .font(.caption)
                                Text(verbatim: "\(event.port)")
                                    .font(.system(.caption, design: .monospaced).bold())
                                Text(eventDescription(event))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
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

    private func eventDescription(_ event: HistoryStore.Event) -> String {
        var parts = [event.processName, event.kind == .opened ? "opened" : "closed"]
        if let projectName = event.projectName {
            parts.insert(projectName, at: 1)
        }
        return parts.joined(separator: " · ")
    }
}
