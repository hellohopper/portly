import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: PortStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.ports.isEmpty {
                Text("No listening ports")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(store.ports) { port in
                    PortRow(info: port, onKill: { store.kill(port) })
                    Divider()
                }
            }

            HStack {
                Button("Refresh") { store.refresh() }
                Spacer()
                Button("Quit Porty") { NSApplication.shared.terminate(nil) }
            }
            .padding(8)
        }
        .frame(width: 320)
    }
}

private struct PortRow: View {
    let info: PortInfo
    let onKill: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(":\(info.port)")
                    .font(.system(.body, design: .monospaced).bold())
                Text("\(info.processName) · pid \(info.pid) · \(info.proto)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive, action: onKill) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
