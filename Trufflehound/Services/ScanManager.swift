import Foundation
import SwiftUI
import UserNotifications

/// Manages scanning state and scheduling
@Observable
@MainActor
final class ScanManager {
    /// Current scan state
    enum ScanState: Equatable {
        case idle
        case scanning
        case error(String)
    }

    /// All findings from the last scan
    private(set) var allFindings: [Finding] = []

    /// Set of seen finding keys for deduplication
    @ObservationIgnored
    private var seenFindingKeys: Set<String> = []

    /// Current scan state
    private(set) var state: ScanState = .idle

    /// Last scan timestamp
    private(set) var lastScanTime: Date?

    /// Duration of last scan in seconds
    private(set) var lastScanDuration: TimeInterval?

    /// Trufflehog version info (for update detection)
    private(set) var versionInfo: TrufflehogVersionInfo?

    /// Timer for scheduled scans
    @ObservationIgnored
    private var scanTimer: Timer?

    /// The trufflehog runner
    @ObservationIgnored
    private let runner = TrufflehogRunner()

    /// Dismissed findings store
    let dismissedStore = DismissedStore()

    /// Filtered findings (excluding dismissed)
    var findings: [Finding] {
        allFindings.filter { !dismissedStore.isDismissed($0) }
    }

    /// Whether a scan is in progress
    var isScanning: Bool {
        state == .scanning
    }

    /// Error message if in error state
    var errorMessage: String? {
        if case .error(let message) = state {
            return message
        }
        return nil
    }

    // MARK: - Settings (read from UserDefaults)

    @ObservationIgnored
    private let defaults = UserDefaults.standard

    var scanIntervalMinutes: Int {
        get { defaults.object(forKey: "scanInterval") as? Int ?? 60 }
        set { defaults.set(newValue, forKey: "scanInterval") }
    }

    var targetDirectory: String {
        get { defaults.string(forKey: "targetDirectory") ?? "~" }
        set { defaults.set(newValue, forKey: "targetDirectory") }
    }

    var trufflehogPath: String {
        get { defaults.string(forKey: "trufflehogPath") ?? "" }
        set { defaults.set(newValue, forKey: "trufflehogPath") }
    }

    var autoScanEnabled: Bool {
        get { defaults.object(forKey: "autoScanEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoScanEnabled") }
    }

    var notifyOnScanStart: Bool {
        get { defaults.object(forKey: "notifyOnScanStart") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "notifyOnScanStart") }
    }

    var notifyOnScanComplete: Bool {
        get { defaults.object(forKey: "notifyOnScanComplete") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notifyOnScanComplete") }
    }

    /// Resolved binary path (custom or auto-detected)
    var resolvedBinaryPath: String? {
        if !trufflehogPath.isEmpty {
            return trufflehogPath
        }
        return TrufflehogRunner.findBinaryPath()
    }

    // MARK: - Scanning

    /// Start a manual scan with streaming results
    func scan() async {
        guard state != .scanning else { return }

        state = .scanning
        // Don't clear findings - preserve the list and add new ones
        // seenFindingKeys already contains keys from previous findings

        let findingsCountBefore = allFindings.count
        let scanStartTime = Date()

        if notifyOnScanStart {
            sendNotification(
                title: "Trufflehound", body: "Scanning for secrets...")
        }

        do {
            try await runner.scan(
                directory: targetDirectory,
                binaryPath: trufflehogPath.isEmpty ? nil : trufflehogPath,
                onFinding: { [weak self] finding in
                    Task { @MainActor in
                        guard let self = self else { return }
                        // Deduplication using finding.id (secure hash)
                        if !self.seenFindingKeys.contains(finding.id) {
                            self.seenFindingKeys.insert(finding.id)
                            self.allFindings.append(finding)
                        }
                    }
                }
            )
            lastScanTime = Date()
            lastScanDuration = Date().timeIntervalSince(scanStartTime)
            state = .idle

            let newFindingsCount = allFindings.count - findingsCountBefore

            // Only notify if there were new findings
            if notifyOnScanComplete && newFindingsCount > 0 {
                sendNotification(
                    title: "Trufflehog",
                    body: "Found \(newFindingsCount) new secret\(newFindingsCount == 1 ? "" : "s")")
            }
        } catch {
            state = .error(error.localizedDescription)
            if notifyOnScanComplete {
                sendNotification(title: "Trufflehog", body: error.localizedDescription)
            }
        }
    }

    /// Send a user notification
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Request notification permissions
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
        }
    }

    /// Cancel the current scan
    func cancelScan() {
        Task {
            await runner.cancel()
            state = .idle
        }
    }

    /// Start scheduled scanning
    func startScheduledScanning() {
        stopScheduledScanning()

        guard autoScanEnabled else { return }

        let interval = TimeInterval(scanIntervalMinutes * 60)

        scanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                await self?.scan()
            }
        }

        // Run initial scan
        Task {
            await scan()
        }
    }

    /// Stop scheduled scanning
    func stopScheduledScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    /// Update the scan schedule (call when settings change)
    func updateSchedule() {
        if autoScanEnabled {
            startScheduledScanning()
        } else {
            stopScheduledScanning()
        }
    }

    /// Check for trufflehog updates
    func checkForUpdates() async {
        let binaryPath = trufflehogPath.isEmpty ? nil : trufflehogPath
        versionInfo = await TrufflehogRunner.checkForUpdates(binaryPath: binaryPath)
    }

    // MARK: - Finding Management

    /// Dismiss a finding
    func dismiss(_ finding: Finding) {
        dismissedStore.dismiss(finding)
    }

    /// Restore a dismissed finding
    func restore(_ finding: Finding) {
        dismissedStore.restore(finding)
    }

    // MARK: - Export

    /// Export findings to CSV file with save dialog
    func exportToCSV(findings: [Finding]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "trufflehound-findings.csv"
        panel.title = "Export Findings"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                let csv = CSVExporter.export(findings: findings)
                try csv.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to export CSV: \(error)")
            }
        }
    }
}
