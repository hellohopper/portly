import SwiftUI

/// The small "type a value, press Save" popover behind both the per-port label and
/// the `.localhost` name editors -- same begin/commit/validate shape, so it lives in
/// one place rather than being written out twice.
struct InlineEditPopover: View {
    let placeholder: String
    /// Rendered after the field, e.g. ".localhost:7777".
    var suffix: String?
    var fieldWidth: CGFloat = 160
    @Binding var text: String
    /// Returns an error message to show, or nil once the value was accepted.
    let onCommit: () -> String?

    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(placeholder, text: $text, onCommit: commit)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: fieldWidth)
                if let suffix {
                    Text(suffix)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Save", action: commit)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(10)
    }

    private func commit() {
        errorMessage = onCommit()
    }
}
