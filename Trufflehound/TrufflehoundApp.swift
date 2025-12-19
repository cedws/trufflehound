import SwiftUI

@main
struct TrufflehoundApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var scanManager = ScanManager()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView(scanManager: scanManager)
                .onAppear {
                    scanManager.requestNotificationPermission()
                    appDelegate.scanManager = scanManager
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // Replace the default About menu item
            CommandGroup(replacing: .appInfo) {
                Button("About Trufflehound") {
                    openWindow(id: "about")
                }
            }

            CommandGroup(after: .newItem) {
                Button("Scan Now") {
                    Task {
                        await scanManager.scan()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(scanManager.isScanning)

                Divider()

                Button("Export to CSV...") {
                    scanManager.exportToCSV(findings: scanManager.findings)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(scanManager.findings.isEmpty)
            }
        }

        #if os(macOS)
            Settings {
                SettingsView()
            }

            Window("About Trufflehound", id: "about") {
                AboutView()
            }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
        #endif
    }
}

// MARK: - App Delegate for background behavior

class AppDelegate: NSObject, NSApplicationDelegate {
    var scanManager: ScanManager?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when window closes - keep running in background
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        // Reopen main window when dock icon is clicked
        if !flag {
            for window in sender.windows {
                if window.canBecomeMain {
                    window.makeKeyAndOrderFront(self)
                    return true
                }
            }
        }
        return true
    }
}

// MARK: - About View

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Trufflehound")
                .font(.title)
                .fontWeight(.bold)

            Text("A tool for scanning your filesystem for secrets and credentials.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .padding(.horizontal, 40)

            VStack(spacing: 8) {
                Text("Powered by")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link(destination: URL(string: "https://github.com/trufflesecurity/trufflehog")!) {
                    HStack {
                        Image(systemName: "link")
                        Text("Trufflehog")
                    }
                    .font(.headline)
                }
            }

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: 320, height: 340)
    }
}
