import PortlyCore
import SwiftUI

/// Who is currently connected to a port. Throughput says bytes are moving; this says
/// whether that's your browser, your worker, or nothing at all.
struct PeersPopover: View {
    let port: Int
    let peers: [ConnectionResolver.Peer]
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connected to port \(port)")
                .font(.subheadline.bold())

            if isLoading {
                ProgressView().controlSize(.small)
            } else if peers.isEmpty {
                Text("No established connections.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(peers) { peer in
                    HStack(spacing: 6) {
                        Image(systemName: peer.processName == nil ? "network" : "app.dashed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(peer.displayName)
                            .font(.caption)
                        Spacer()
                        Text(peer.address)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}
