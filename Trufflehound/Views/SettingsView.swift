import SwiftUI

struct SettingsView: View {
    @AppStorage("scanInterval") private var scanIntervalMinutes: Int = 60
    @AppStorage("targetDirectory") private var targetDirectory: String = "~"
    @AppStorage("trufflehogPath") private var trufflehogPath: String = ""
    @AppStorage("autoScanEnabled") private var autoScanEnabled: Bool = true
    @AppStorage("notifyOnScanStart") private var notifyOnScanStart: Bool = false
    @AppStorage("notifyOnScanComplete") private var notifyOnScanComplete: Bool = true

    @State private var detectedBinaryPath: String? = TrufflehogRunner.findBinaryPath()

    var body: some View {
        Form {
            // Scanning Section
            Section {
                Toggle("Enable automatic scanning", isOn: $autoScanEnabled)

                if autoScanEnabled {
                    Picker("Scan interval", selection: $scanIntervalMinutes) {
                        Text("Every 15 minutes").tag(15)
                        Text("Every 30 minutes").tag(30)
                        Text("Every hour").tag(60)
                        Text("Every 2 hours").tag(120)
                        Text("Every 4 hours").tag(240)
                        Text("Every 8 hours").tag(480)
                        Text("Once a day").tag(1440)
                    }
                }
            } header: {
                Text("Scanning")
            }

            // Notifications Section
            Section {
                Toggle("Notify when scan starts", isOn: $notifyOnScanStart)
                Toggle("Notify when scan completes", isOn: $notifyOnScanComplete)
            } header: {
                Text("Notifications")
            }

            // Target Directory Section
            Section {
                HStack {
                    TextField("Directory to scan", text: $targetDirectory)
                        .textFieldStyle(.roundedBorder)

                    Button("Choose...") {
                        chooseDirectory()
                    }
                }

                Text("The directory that will be scanned for secrets. Use ~ for home directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Target Directory")
            }

            // Trufflehog Binary Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Custom path (optional)", text: $trufflehogPath)
                            .textFieldStyle(.roundedBorder)

                        Button("Browse...") {
                            chooseBinary()
                        }
                    }

                    if trufflehogPath.isEmpty {
                        if let detected = detectedBinaryPath {
                            Label(
                                "Auto-detected: \(detected)", systemImage: "checkmark.circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.green)
                        } else {
                            Label(
                                "Trufflehog not found in PATH",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    } else {
                        if FileManager.default.isExecutableFile(atPath: trufflehogPath) {
                            Label("Binary found", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Label(
                                "Binary not found at specified path",
                                systemImage: "xmark.circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                    }
                }

                Text("Leave empty to auto-detect trufflehog from PATH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Trufflehog Binary")
            }

            // About Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Trufflehound")
                        .font(.headline)

                    Text("A native macOS wrapper for Trufflehog secret detection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link(
                        "Trufflehog on GitHub",
                        destination: URL(string: "https://github.com/trufflesecurity/trufflehog")!
                    )
                    .font(.caption)
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 400)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Directory to Scan"

        if panel.runModal() == .OK, let url = panel.url {
            targetDirectory = url.path
        }
    }

    private func chooseBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose Trufflehog Binary"
        panel.message = "Select the trufflehog executable"

        if panel.runModal() == .OK, let url = panel.url {
            trufflehogPath = url.path
        }
    }
}

#Preview {
    SettingsView()
}
