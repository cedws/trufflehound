import CryptoKit
import Foundation

/// Errors that can occur when running trufflehog
enum TrufflehogError: LocalizedError {
    case binaryNotFound(String)
    case executionFailed(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let path):
            return "Trufflehog binary not found at: \(path)"
        case .executionFailed(let message):
            return "Trufflehog execution failed: \(message)"
        case .parseError(let message):
            return "Failed to parse trufflehog output: \(message)"
        }
    }
}

/// Version information for trufflehog
struct TrufflehogVersionInfo: Sendable {
    let installedVersion: String
    let latestVersion: String?
    let updateAvailable: Bool
}

/// Service responsible for executing trufflehog and parsing results
actor TrufflehogRunner {

    /// Default paths to search for trufflehog binary
    private static let defaultPaths = [
        "/opt/homebrew/bin/trufflehog",
        "/usr/local/bin/trufflehog",
        "/usr/bin/trufflehog",
    ]

    /// Currently running process (for cancellation)
    private var currentProcess: Process?

    /// Find the trufflehog binary path
    static func findBinaryPath() -> String? {
        for path in defaultPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Try using `which` as fallback
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["trufflehog"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines),
                !path.isEmpty
            {
                return path
            }
        } catch {
            // Ignore errors from which
        }

        return nil
    }

    /// Run trufflehog against the specified directory with streaming output
    /// - Parameters:
    ///   - directory: The directory to scan
    ///   - binaryPath: Path to the trufflehog binary (auto-detected if nil)
    ///   - onFinding: Callback with finding - caller handles dedup using finding.id
    func scan(
        directory: String,
        binaryPath: String? = nil,
        onFinding: @escaping @Sendable (Finding) -> Void
    ) async throws {
        let resolvedPath = binaryPath ?? TrufflehogRunner.findBinaryPath()

        guard let executablePath = resolvedPath,
            FileManager.default.isExecutableFile(atPath: executablePath)
        else {
            throw TrufflehogError.binaryNotFound(resolvedPath ?? "not found")
        }

        let expandedDirectory = (directory as NSString).expandingTildeInPath

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [
            "--no-update",
            "--filter-unverified",
            "filesystem",
            "--results", "verified",
            "-j",
            expandedDirectory,
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        currentProcess = process

        do {
            try process.run()
        } catch {
            currentProcess = nil
            throw TrufflehogError.executionFailed(error.localizedDescription)
        }

        // Stream output line by line
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                let fileHandle = stdoutPipe.fileHandleForReading
                var buffer = Data()

                while true {
                    let chunk = fileHandle.availableData
                    if chunk.isEmpty {
                        break
                    }

                    buffer.append(chunk)

                    // Process complete lines
                    while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                        let lineData = buffer.subdata(
                            in: buffer.startIndex..<newlineRange.lowerBound)
                        buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                        guard !lineData.isEmpty else { continue }

                        // Use secure parser - secret is hashed and immediately discarded
                        if let finding = try? SecureFindingParser.parse(jsonData: lineData) {
                            onFinding(finding)
                        }
                    }
                }

                // Process any remaining data in buffer
                if !buffer.isEmpty {
                    if let finding = try? SecureFindingParser.parse(jsonData: buffer) {
                        onFinding(finding)
                    }
                }

                process.waitUntilExit()

                // Check process exit status
                if process.terminationStatus != 0 {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage =
                        String(data: stderrData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                    continuation.resume(throwing: TrufflehogError.executionFailed(errorMessage))
                } else {
                    continuation.resume()
                }
            }
        }

        currentProcess = nil
    }

    /// Cancel the current scan if running
    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
    }

    /// Scan a single file and return the raw secret for a specific finding
    /// - Parameters:
    ///   - filePath: Path to the file to scan
    ///   - findingID: The secure hash ID of the finding (hash of filePath+line+secret)
    ///   - binaryPath: Path to the trufflehog binary (auto-detected if nil)
    /// - Returns: The raw secret value if found, nil otherwise
    func scanFileForSecret(
        filePath: String,
        findingID: String,
        binaryPath: String? = nil
    ) async throws -> String? {
        let resolvedPath = binaryPath ?? TrufflehogRunner.findBinaryPath()

        guard let executablePath = resolvedPath,
            FileManager.default.isExecutableFile(atPath: executablePath)
        else {
            throw TrufflehogError.binaryNotFound(resolvedPath ?? "not found")
        }

        let expandedPath = (filePath as NSString).expandingTildeInPath
        let idToFind = findingID

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = [
                    "--no-update",
                    "--filter-unverified",
                    "filesystem",
                    "--results", "verified",
                    "-j",
                    expandedPath,
                ]

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(
                        throwing: TrufflehogError.executionFailed(error.localizedDescription))
                    return
                }

                // Read all output
                let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                print("scanFileForSecret: Process exited, got \(outputData.count) bytes")

                let decoder = JSONDecoder()
                let lines = outputData.split(separator: UInt8(ascii: "\n"))

                print(
                    "scanFileForSecret: Found \(lines.count) lines, looking for ID: \(idToFind)"
                )

                for lineData in lines {
                    guard !lineData.isEmpty else { continue }

                    do {
                        let rawFinding = try decoder.decode(RawFinding.self, from: Data(lineData))

                        // Compute secure hash ID and compare
                        let foundID = rawFinding.secureHash

                        print("scanFileForSecret: Comparing \(foundID) vs \(idToFind)")

                        if foundID == idToFind {
                            print("scanFileForSecret: MATCH FOUND!")
                            continuation.resume(returning: rawFinding.raw)
                            return
                        }
                    } catch {
                        // Skip unparseable lines (like log messages)
                    }
                }

                print("scanFileForSecret: No match found, returning nil")
                continuation.resume(returning: nil)
            }
        }
    }

    /// Get the installed trufflehog version
    /// - Parameter binaryPath: Path to the trufflehog binary (auto-detected if nil)
    /// - Returns: The version string (e.g., "3.63.1") or nil if not found
    static func getInstalledVersion(binaryPath: String? = nil) -> String? {
        let resolvedPath = binaryPath ?? findBinaryPath()

        guard let executablePath = resolvedPath,
            FileManager.default.isExecutableFile(atPath: executablePath)
        else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines)
            {
                // Output is typically "trufflehog 3.63.1" - extract just the version
                let components = output.split(separator: " ")
                if components.count >= 2 {
                    return String(components[1])
                }
                return output
            }
        } catch {
            // Ignore errors
        }

        return nil
    }

    /// Fetch the latest trufflehog version from GitHub releases
    /// - Returns: The latest version string or nil if fetch failed
    static func fetchLatestVersion() async -> String? {
        guard
            let url = URL(
                string: "https://api.github.com/repos/trufflesecurity/trufflehog/releases/latest")
        else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                return nil
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tagName = json["tag_name"] as? String
            {
                // Tag is typically "v3.63.1" - strip the leading "v"
                return tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            }
        } catch {
            // Ignore errors - update check is non-critical
        }

        return nil
    }

    /// Check for trufflehog updates
    /// - Parameter binaryPath: Path to the trufflehog binary (auto-detected if nil)
    /// - Returns: Version info including whether an update is available
    static func checkForUpdates(binaryPath: String? = nil) async -> TrufflehogVersionInfo? {
        guard let installedVersion = getInstalledVersion(binaryPath: binaryPath) else {
            return nil
        }

        let latestVersion = await fetchLatestVersion()

        let updateAvailable: Bool
        if let latest = latestVersion {
            updateAvailable = compareVersions(installed: installedVersion, latest: latest)
        } else {
            updateAvailable = false
        }

        return TrufflehogVersionInfo(
            installedVersion: installedVersion,
            latestVersion: latestVersion,
            updateAvailable: updateAvailable
        )
    }

    /// Compare version strings to determine if an update is available
    /// - Returns: true if latest is newer than installed
    private static func compareVersions(installed: String, latest: String) -> Bool {
        let installedParts = installed.split(separator: ".").compactMap { Int($0) }
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(installedParts.count, latestParts.count) {
            let installedPart = i < installedParts.count ? installedParts[i] : 0
            let latestPart = i < latestParts.count ? latestParts[i] : 0

            if latestPart > installedPart {
                return true
            } else if latestPart < installedPart {
                return false
            }
        }

        return false
    }
}
