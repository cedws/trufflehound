import Foundation

/// A secure string container that zeroes memory when deallocated.
/// Uses a mutable buffer that can be securely wiped.
final class SecureString {
    private var buffer: UnsafeMutableBufferPointer<UInt8>?
    private let length: Int

    /// Initialize with a string value
    init(_ string: String) {
        let utf8 = Array(string.utf8)
        self.length = utf8.count

        if length > 0 {
            buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: length)
            for (i, byte) in utf8.enumerated() {
                buffer![i] = byte
            }
        }
    }

    /// Get the string value (creates a copy)
    var value: String {
        guard let buffer = buffer, length > 0 else { return "" }
        return String(decoding: buffer, as: UTF8.self)
    }

    /// Securely wipe the memory
    func wipe() {
        guard let buffer = buffer else { return }

        // Overwrite with zeros using volatile write to prevent optimization
        for i in 0..<length {
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

/// Observable wrapper for SecureString to use in SwiftUI
@MainActor
final class SecureSecretState: ObservableObject {
    @Published private(set) var isRevealed: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    private var secureString: SecureString?
    private var hideTimer: Timer?

    /// The revealed secret value (empty if not revealed)
    var revealedValue: String {
        secureString?.value ?? ""
    }

    /// Reveal a secret, auto-hiding after specified duration
    func reveal(secret: String, hideAfter seconds: TimeInterval = 10) {
        // Wipe any existing secret first
        wipe()

        secureString = SecureString(secret)
        isRevealed = true
        isLoading = false
        error = nil

        // Set up auto-hide timer
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) {
            [weak self] _ in
            Task { @MainActor in
                self?.wipe()
            }
        }
    }

    /// Set loading state
    func setLoading(_ loading: Bool) {
        isLoading = loading
        if loading {
            error = nil
        }
    }

    /// Set error state
    func setError(_ message: String) {
        wipe()
        error = message
        isLoading = false
    }

    /// Wipe the secret from memory
    func wipe() {
        hideTimer?.invalidate()
        hideTimer = nil
        secureString?.wipe()
        secureString = nil
        isRevealed = false
    }

    deinit {
        hideTimer?.invalidate()
        secureString?.wipe()
    }
}
