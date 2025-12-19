import Foundation

/// Exports findings to CSV format
enum CSVExporter {

    /// Export findings to CSV string
    /// - Parameter findings: The findings to export
    /// - Returns: CSV formatted string
    static func export(findings: [Finding]) -> String {
        var lines: [String] = []

        // Header - NOTE: No raw secrets exported for security
        let headers = [
            "Detector",
            "File Path",
            "File Name",
            "Line",
            "Verified",
            "Decoder",
        ]
        lines.append(headers.map { escapeCSV($0) }.joined(separator: ","))

        // Data rows
        for finding in findings {
            let row = [
                finding.detectorName,
                finding.filePath ?? "",
                finding.fileName,
                finding.line.map(String.init) ?? "",
                finding.verified ? "Yes" : "No",
                finding.decoderName,
            ]
            lines.append(row.map { escapeCSV($0) }.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    /// Escape a value for CSV format
    private static func escapeCSV(_ value: String) -> String {
        let needsQuoting =
            value.contains(",") || value.contains("\n") || value.contains("\r")
            || value.contains("\"")

        if needsQuoting {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }

        return value
    }
}
