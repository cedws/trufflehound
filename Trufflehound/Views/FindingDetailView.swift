import SwiftUI

struct FindingDetailView: View {
    let finding: Finding
    let isDismissed: Bool
    let onDismiss: () -> Void
    let onRestore: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                header

                Divider()

                // Main Info
                Group {
                    detailSection(title: "Detector", value: finding.detectorName)

                    if let displayPath = finding.displayPath {
                        filePathSection(path: displayPath, fullPath: finding.filePath)
                    }

                    // Secret reveal box (under file path)
                    SecretRevealBox(finding: finding, onSecretNotFound: onDismiss)

                    if let line = finding.line {
                        detailSection(title: "Line", value: String(line))
                    }

                    detailSection(
                        title: "Verification",
                        value: finding.verified ? "Verified (confirmed active)" : "Unverified")

                    detailSection(title: "Decoder", value: finding.decoderName)
                }

                // Extra Data
                if let extraData = finding.extraData, !extraData.isEmpty {
                    Divider()
                    extraDataSection(extraData)
                }

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 300)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Filename and line (like list view style)
            HStack {
                Text(finding.fileName)
                    .font(.title2)
                    .fontWeight(.bold)
                if let line = finding.line {
                    Text(":\(line)")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                statusBadge

                Text(finding.detectorName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Action buttons - side by side
            HStack(spacing: 8) {
                if let path = finding.filePath {
                    Button {
                        openFile(path)
                    } label: {
                        Label("Open", systemImage: "doc.text")
                    }

                    Button {
                        revealInFinder(path)
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                }

                if isDismissed {
                    Button {
                        onRestore()
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                } else {
                    Button {
                        onDismiss()
                    } label: {
                        Label("Dismiss", systemImage: "xmark.circle")
                    }
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        if isDismissed { return .gray }
        return finding.verified ? .red : .orange
    }

    private var statusText: String {
        if isDismissed { return "Dismissed" }
        return finding.verified ? "Verified" : "Unverified"
    }

    private func filePathSection(path: String, fullPath: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("File Path")
                .font(.headline)

            HStack {
                Text(path)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)

                Spacer()

                Button {
                    // Copy the full path, not the display path
                    copyToClipboard(fullPath ?? path)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy file path")
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }

    private func detailSection(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)

            Text(value)
                .textSelection(.enabled)
        }
    }

    private func extraDataSection(_ data: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Additional Data")
                .font(.headline)

            ForEach(Array(data.keys.sorted()), id: \.self) { key in
                if let value = data[key] {
                    HStack(alignment: .top) {
                        Text(key)
                            .foregroundStyle(.secondary)
                            .frame(width: 100, alignment: .trailing)

                        if let url = URL(string: value),
                            url.scheme == "http" || url.scheme == "https"
                        {
                            Link(value, destination: url)
                                .foregroundStyle(.blue)
                        } else {
                            Text(value)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func revealInFinder(_ path: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openFile(_ path: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        NSWorkspace.shared.open(url)
    }
}

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Select a Finding")
                .font(.headline)

            Text("Choose a finding from the list to view details")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
