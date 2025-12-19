import Foundation

/// Versioned storage format for dismissed findings
private struct DismissedStoreData: Codable {
    /// Schema version - increment when changing format
    let version: Int
    /// Dismissed finding IDs (secure hashes)
    let dismissedIDs: [String]

    static let currentVersion = 1

    init(dismissedIDs: Set<String>) {
        self.version = Self.currentVersion
        self.dismissedIDs = Array(dismissedIDs)
    }
}

/// Manages persistence of dismissed finding IDs
@Observable
final class DismissedStore {
    /// Set of dismissed finding hashes
    private(set) var dismissedIDs: Set<String> = []

    /// File URL for storing dismissed findings
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let appFolder = appSupport.appendingPathComponent("Trufflehound", isDirectory: true)

        // Create app folder if needed
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        self.fileURL = appFolder.appendingPathComponent("dismissed.json")

        loadFromDisk()
    }

    /// Check if a finding is dismissed (by its secure hash ID)
    func isDismissed(_ finding: Finding) -> Bool {
        dismissedIDs.contains(finding.id)
    }

    /// Dismiss a finding (by its secure hash ID)
    func dismiss(_ finding: Finding) {
        dismissedIDs.insert(finding.id)
        saveToDisk()
    }

    /// Restore a dismissed finding (by its secure hash ID)
    func restore(_ finding: Finding) {
        dismissedIDs.remove(finding.id)
        saveToDisk()
    }

    /// Restore a finding by ID
    func restore(id: String) {
        dismissedIDs.remove(id)
        saveToDisk()
    }

    /// Clear all dismissed findings
    func clearAll() {
        dismissedIDs.removeAll()
        saveToDisk()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)

            // Try to decode as versioned format first
            if let storeData = try? JSONDecoder().decode(DismissedStoreData.self, from: data) {
                // Handle migrations based on version if needed in future
                switch storeData.version {
                case 1:
                    dismissedIDs = Set(storeData.dismissedIDs)
                default:
                    // Unknown future version - try to load what we can
                    dismissedIDs = Set(storeData.dismissedIDs)
                }
            } else {
                // Legacy format: plain array of strings
                let ids = try JSONDecoder().decode([String].self, from: data)
                dismissedIDs = Set(ids)
                // Migrate to new format
                saveToDisk()
            }
        } catch {
            print("Failed to load dismissed findings: \(error)")
        }
    }

    private func saveToDisk() {
        do {
            let storeData = DismissedStoreData(dismissedIDs: dismissedIDs)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(storeData)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save dismissed findings: \(error)")
        }
    }
}
