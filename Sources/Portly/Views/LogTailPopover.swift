import PortlyCore
import SwiftUI
import AppKit

/// The last lines of a process's log, refreshed while open -- enough to see why a
/// server just crashed without leaving the menu bar.
struct LogTailPopover: View {
    let path: String

    @State private var lines: [String] = []
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                    .buttonStyle(.borderless)
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                    .buttonStyle(.borderless)
            }

            if lines.isEmpty {
                Text("The log is empty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(verbatim: lines.joined(separator: "\n"))
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(height: 260)
                    .onAppear { proxy.scrollTo("bottom") }
                    .onChange(of: lines) { _ in proxy.scrollTo("bottom") }
                }
            }
        }
        .padding(12)
        .frame(width: 480)
        .onAppear(perform: reload)
        .onReceive(timer) { _ in reload() }
    }

    private func reload() {
        let path = path
        Task {
            let latest = await Task.detached { LaunchLog.tail(of: path, maxLines: 200) }.value
            if latest != lines { lines = latest }
        }
    }
}
