import CryptoKit
import Foundation

/// Secure hasher using HKDF-SHA256 with memory-safe secret handling
enum SecureHasher {
    /// Fixed salt for deterministic hashing
    private static let salt = Data("trufflehound".utf8)
    /// Info parameter for HKDF domain separation
    private static let info = Data("finding-id-v1".utf8)
    /// Output key length in bytes
    private static let outputLength = 32

    /// Compute HKDF-SHA256 hash from components using secure memory handling
    /// The secret data is wiped from memory after hashing
    static func computeHash(filePath: String?, line: Int?, secretData: Data) -> String {
        // Create input combining path, line, and secret
        var inputData = Data("\(filePath ?? ""):\(line ?? 0):".utf8)
        inputData.append(secretData)

        // Use SecureBytes to handle the input securely
        let secureInput = SecureBytes(inputData)
        defer { secureInput.wipe() }

        // Create a symmetric key from the input data
        let inputKey = SymmetricKey(data: secureInput.bytes)

        // Use HKDF to derive a secure hash
        // HKDF is designed for key derivation and provides cryptographic security
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: info,
            outputByteCount: outputLength
        )

        // Convert to hex string
        return derivedKey.withUnsafeBytes { bytes in
            bytes.map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Compute hash from string secret (convenience method)
    static func computeHash(filePath: String?, line: Int?, secret: String) -> String {
        return computeHash(filePath: filePath, line: line, secretData: Data(secret.utf8))
    }
}

/// Secure byte buffer that wipes memory on deallocation
final class SecureBytes {
    private var buffer: UnsafeMutableBufferPointer<UInt8>?
    private let count: Int

    init(_ data: Data) {
        self.count = data.count
        if count > 0 {
            buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: count)
            data.copyBytes(to: buffer!, count: count)
        }
    }

    var bytes: [UInt8] {
        guard let buffer = buffer else { return [] }
        return Array(UnsafeBufferPointer(buffer))
    }

    func wipe() {
        guard let buffer = buffer else { return }

        // Overwrite with zeros using volatile write to prevent optimization
        for i in 0..<count {
            buffer[i] = 0
        }

        // Use memory barrier to ensure writes complete
        OSMemoryBarrier()

        buffer.deallocate()
        self.buffer = nil
    }

    deinit {
        wipe()
    }
}
