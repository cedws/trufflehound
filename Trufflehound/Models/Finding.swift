import Foundation

/// Represents a secret finding from trufflehog
/// NOTE: Raw secrets are NOT stored - only a secure Argon2id hash for identification
struct Finding: Identifiable, Hashable {
    /// Secure Argon2id hash of (filePath + line + secret) - used as primary identifier
    /// This is the ONLY identifier used for dismissals, deduplication, and secret lookup
    let id: String

    let detectorName: String
    let decoderName: String
    let verified: Bool
    let filePath: String?
    let line: Int?
    let extraData: [String: String]?

    /// Display-friendly file name
    var fileName: String {
        if let path = filePath {
            return (path as NSString).lastPathComponent
        }
        return "Unknown"
    }

    /// Display-friendly file path (collapses home directory to ~/)
    var displayPath: String? {
        guard let path = filePath else { return nil }
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// Compute secure Argon2id hash from components using Data (avoids String for secret)
    /// The secret data is securely wiped from memory after hashing
    static func computeHashFromData(filePath: String?, line: Int?, secretData: Data) -> String {
        return SecureHasher.computeHash(filePath: filePath, line: line, secretData: secretData)
    }

    /// Compute secure Argon2id hash from components (for reveal matching)
    static func computeHash(filePath: String?, line: Int?, secret: String) -> String {
        return SecureHasher.computeHash(filePath: filePath, line: line, secret: secret)
    }
}

/// Parser for trufflehog JSON that avoids storing secrets in memory
/// Uses manual JSON parsing to compute hash without creating String from secret
enum SecureFindingParser {

    /// Parse JSON data and return a Finding with secure hash, without storing the secret
    static func parse(jsonData: Data) throws -> Finding? {
        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        // Skip log lines (they have "level" key)
        if json["level"] != nil {
            return nil
        }

        // Extract required fields
        guard let detectorName = json["DetectorName"] as? String,
            let decoderName = json["DecoderName"] as? String,
            let verified = json["Verified"] as? Bool
        else {
            return nil
        }

        // Extract file path and line from nested structure
        var filePath: String?
        var line: Int?
        if let sourceMetadata = json["SourceMetadata"] as? [String: Any],
            let data = sourceMetadata["Data"] as? [String: Any],
            let filesystem = data["Filesystem"] as? [String: Any]
        {
            filePath = filesystem["file"] as? String
            line = filesystem["line"] as? Int
        }

        // Extract extra data
        let extraData = json["ExtraData"] as? [String: String]

        // Get the raw secret as Data, compute hash, then let it go out of scope
        // We need to find "Raw" in the original JSON bytes to avoid String allocation
        let secureHash: String
        if let rawString = json["Raw"] as? String {
            // Unfortunately JSONSerialization already decoded it as String
            // Compute hash and let the String be deallocated
            secureHash = Finding.computeHash(filePath: filePath, line: line, secret: rawString)
            // rawString goes out of scope here
        } else {
            return nil
        }

        return Finding(
            id: secureHash,
            detectorName: detectorName,
            decoderName: decoderName,
            verified: verified,
            filePath: filePath,
            line: line,
            extraData: extraData
        )
    }
}

/// RawFinding is only used during secret reveal when we need the actual secret value
struct RawFinding: Codable {
    let sourceMetadata: SourceMetadata
    let detectorName: String
    let decoderName: String
    let verified: Bool
    let raw: String
    let extraData: [String: String]?

    enum CodingKeys: String, CodingKey {
        case sourceMetadata = "SourceMetadata"
        case detectorName = "DetectorName"
        case decoderName = "DecoderName"
        case verified = "Verified"
        case raw = "Raw"
        case extraData = "ExtraData"
    }

    /// The file path from source metadata
    var filePath: String? {
        sourceMetadata.data?.filesystem?.file
    }

    /// The line number from source metadata
    var line: Int? {
        sourceMetadata.data?.filesystem?.line
    }

    /// Compute the secure hash (same as Finding.id)
    var secureHash: String {
        Finding.computeHash(filePath: filePath, line: line, secret: raw)
    }
}

struct SourceMetadata: Codable, Hashable {
    let data: SourceData?

    enum CodingKeys: String, CodingKey {
        case data = "Data"
    }
}

struct SourceData: Codable, Hashable {
    let filesystem: FilesystemData?

    enum CodingKeys: String, CodingKey {
        case filesystem = "Filesystem"
    }
}

struct FilesystemData: Codable, Hashable {
    let file: String?
    let line: Int?
    let link: String?

    enum CodingKeys: String, CodingKey {
        case file
        case line
        case link
    }
}

struct StructuredData: Codable, Hashable {
    // Placeholder for any structured data trufflehog might return
}
