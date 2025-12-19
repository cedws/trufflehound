import SwiftUI

struct FindingsTableView: View {
    @Bindable var scanManager: ScanManager
    @Binding var selectedFindingID: String?
    @State private var showDismissed = false
    @State private var searchText = ""

    private var displayedFindings: [Finding] {
        let base = showDismissed ? scanManager.allFindings : scanManager.findings

        if searchText.isEmpty {
            return base
        }

        return base.filter { finding in
            finding.detectorName.localizedCaseInsensitiveContains(searchText)
                || (finding.filePath?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Scan controls row
            HStack {
                HStack {
                    if scanManager.isScanning {
                        Button {
                            scanManager.cancelScan()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.bordered)

                        ProgressView()
                            .scaleEffect(0.7)
                            .padding(.leading, 4)
                    } else {
                        Button {
                            Task {
                                await scanManager.scan()
                            }
                        } label: {
                            Label("Scan Now", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(minWidth: 120, alignment: .leading)

                if let lastScan = scanManager.lastScanTime {
                    HStack(spacing: 4) {
                        Text("Last scan: \(lastScan, style: .relative) ago")
                        if let duration = scanManager.lastScanDuration {
                            Text("(\(formatDuration(duration)))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if let versionInfo = scanManager.versionInfo, versionInfo.updateAvailable {
                    Link(
                        destination: URL(
                            string: "https://github.com/trufflesecurity/trufflehog/releases/latest")!
                    ) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(.orange)
                            Text("Update available: \(versionInfo.latestVersion ?? "")")
                                .font(.caption)
                        }
                    }
                    .help("Currently installed: \(versionInfo.installedVersion)")
                }

                Button {
                    scanManager.exportToCSV(findings: displayedFindings)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(displayedFindings.isEmpty)
            }
            .frame(height: 44)
            .padding(.horizontal)
            .background(.bar)
            .task {
                await scanManager.checkForUpdates()
            }

            Divider()

            // Search and filter row
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search findings...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                Toggle("Show Dismissed", isOn: $showDismissed)
                    .toggleStyle(.checkbox)

                Text("\(displayedFindings.count) findings")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            // Table
            if displayedFindings.isEmpty {
                emptyState
            } else {
                Table(displayedFindings, selection: $selectedFindingID) {
                    TableColumn("Status") { finding in
                        StatusBadge(
                            finding: finding,
                            isDismissed: scanManager.dismissedStore.isDismissed(finding))
                    }
                    .width(min: 80, ideal: 90, max: 100)

                    TableColumn("Detector") { finding in
                        Text(finding.detectorName)
                            .fontWeight(.medium)
                    }
                    .width(min: 100, ideal: 120, max: 150)

                    TableColumn("File") { finding in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(finding.fileName)
                                    .fontWeight(.medium)
                                if let line = finding.line {
                                    Text(":\(line)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let path = finding.displayPath {
                                Text(path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .contextMenu {
                            contextMenuItems(for: finding)
                        }
                    }
                    .width(min: 200, ideal: 300)

                    TableColumn("Actions") { finding in
                        ActionButtons(
                            finding: finding,
                            isDismissed: scanManager.dismissedStore.isDismissed(finding),
                            onDismiss: { scanManager.dismiss(finding) },
                            onRestore: { scanManager.restore(finding) }
                        )
                    }
                    .width(80)
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenuItems(for finding: Finding) -> some View {
        if scanManager.dismissedStore.isDismissed(finding) {
            Button {
                scanManager.restore(finding)
            } label: {
                Label("Restore Finding", systemImage: "arrow.uturn.backward")
            }
        } else {
            Button {
                scanManager.dismiss(finding)
            } label: {
                Label("Dismiss Finding", systemImage: "xmark.circle")
            }
        }

        Divider()

        if let path = finding.filePath {
            Button {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            } label: {
                Label("Copy File Path", systemImage: "doc.on.doc")
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.0fs", duration)
        } else if duration < 3600 {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = Int(duration) / 3600
            let minutes = (Int(duration) % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if scanManager.isScanning {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Scanning...")
                    .font(.headline)
            } else if let error = scanManager.errorMessage {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text("Scan Error")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else if scanManager.lastScanTime != nil {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("No Secrets Found")
                    .font(.headline)
                Text("Your scan completed with no verified secrets detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No Scan Results")
                    .font(.headline)
                Text("Click \"Scan Now\" to start scanning for secrets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Supporting Views

struct StatusBadge: View {
    let finding: Finding
    let isDismissed: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
        }
        .accessibilityLabel("Finding status: \(statusText)")
    }

    private var statusColor: Color {
        if isDismissed {
            return .gray
        }
        return finding.verified ? .red : .orange
    }

    private var statusText: String {
        if isDismissed {
            return "Dismissed"
        }
        return finding.verified ? "Verified" : "Unverified"
    }
}

struct ActionButtons: View {
    let finding: Finding
    let isDismissed: Bool
    let onDismiss: () -> Void
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if isDismissed {
                Button(action: onRestore) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Restore finding")
                .accessibilityLabel("Restore finding")
            } else {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Dismiss as false positive")
                .accessibilityLabel("Dismiss finding")
            }
        }
    }
}

#Preview {
    FindingsTableView(
        scanManager: ScanManager(),
        selectedFindingID: .constant(nil)
    )
}
