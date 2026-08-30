import PortlyCore
import SwiftUI

/// "Is anything even hitting this?" for a `.localhost` mapping -- a rolling log of
/// requests the proxy has forwarded, since there's no browser network tab pointed at
/// a reverse proxy.
struct ProxyRequestLogPopover: View {
    let name: String
    let entries: [ProxyRequestLog.Entry]

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent requests to \(name).localhost")
                .font(.subheadline.bold())

            if entries.isEmpty {
                Text("No requests seen yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(entries, id: \.id) { entry in
                            HStack(spacing: 6) {
                                Text(Self.timeFormatter.string(from: entry.date))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(entry.method)
                                    .font(.caption2.monospaced().bold())
                                    .foregroundStyle(Color.accentColor)
                                Text(entry.path)
                                    .font(.caption2.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}
