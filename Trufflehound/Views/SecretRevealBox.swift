import SwiftUI

/// A secure box that reveals a secret on demand, auto-hiding after 10 seconds
struct SecretRevealBox: View {
    let finding: Finding
    var onSecretNotFound: (() -> Void)?

    @StateObject private var secretState = SecureSecretState()
    @State private var remainingSeconds: Int = 10
    @State private var countdownTimer: Timer?
    @State private var isRevealing = false

    private let runner = TrufflehogRunner()

    /// Fixed height for the content box to prevent layout jumps
    private let boxHeight: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Secret Value", systemImage: "key.fill")
                    .font(.headline)

                Spacer()

                if secretState.isRevealed {
                    Text("\(remainingSeconds)s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // Content box with fixed height
            ZStack {
                if secretState.isLoading {
                    loadingContent
                } else if secretState.isRevealed {
                    revealedContent
                } else if let error = secretState.error {
                    errorContent(error)
                } else {
                    hiddenContent
                }
            }
            .frame(height: boxHeight)
        }
        .onChange(of: finding.id) { _, _ in
            hideSecret()
        }
        .onDisappear {
            hideSecret()
        }
    }

    // MARK: - Content Views

    private var loadingContent: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Scanning file for secret...")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var revealedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(secretState.revealedValue)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)

                Spacer()

                Button {
                    copyToClipboard(secretState.revealedValue)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy secret")

                Button {
                    hideSecret()
                } label: {
                    Image(systemName: "eye.slash")
                }
                .buttonStyle(.borderless)
                .help("Hide now")
            }

            // Countdown progress bar
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.red.opacity(0.3))
                    .frame(width: geometry.size.width * CGFloat(remainingSeconds) / 10.0)
                    .animation(.linear(duration: 1), value: remainingSeconds)
            }
            .frame(height: 4)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }

    private func errorContent(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(error)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private var hiddenContent: some View {
        Button {
            revealSecret()
        } label: {
            HStack {
                Image(systemName: "eye")
                Text("Click to reveal secret")
                    .font(.callout)

                Spacer()

                Text("Auto-hides in 10s")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ZStack {
                    Color(nsColor: .controlBackgroundColor)
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.secondary.opacity(0.2))
                            .frame(width: CGFloat.random(in: 60...120), height: 12)
                            .offset(x: CGFloat.random(in: -80...80), y: 0)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reveal secret value")
        .accessibilityHint(
            "Double-tap to reveal the secret. It will automatically hide after 10 seconds.")
    }

    // MARK: - Actions

    private func revealSecret() {
        guard !isRevealing else { return }

        guard let filePath = finding.filePath else {
            secretState.setError("No file path available")
            return
        }

        isRevealing = true
        secretState.setLoading(true)

        Task {
            defer {
                Task { @MainActor in
                    isRevealing = false
                }
            }

            do {
                let secret = try await runner.scanFileForSecret(
                    filePath: filePath,
                    findingID: finding.id
                )

                await MainActor.run {
                    if let secret = secret {
                        remainingSeconds = 10
                        secretState.reveal(secret: secret, hideAfter: 11)  // Extra second for animation
                        startCountdown()
                    } else {
                        secretState.setError("Secret no longer found - dismissing")
                        onSecretNotFound?()
                    }
                }
            } catch {
                await MainActor.run {
                    secretState.setError("\(error.localizedDescription)")
                }
            }
        }
    }

    private func hideSecret() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        secretState.wipe()
        remainingSeconds = 10
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] timer in
            if remainingSeconds > 1 {
                remainingSeconds -= 1
            } else {
                // Stop timer immediately to prevent further decrements
                timer.invalidate()
                countdownTimer = nil
                // Set to 0 to trigger final animation
                remainingSeconds = 0
                // Wait for animation to complete, then hide
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    hideSecret()
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
