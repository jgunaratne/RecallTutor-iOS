import SwiftUI

/// Compact voice-tutor controls — speaker mute/unmute (or connect), and an
/// "Ask Question" mic pill while connected. Designed to sit inside a shared
/// liquid-glass capsule (the lecture/quiz bottom navigation bars), so the
/// buttons carry only tinted state fills rather than their own glass.
struct VoiceControlBar: View {
    let tutor: VoiceTutorManager

    var body: some View {
        HStack(spacing: 6) {
            speakerButton

            if tutor.status == .connected {
                micPill
            }

            if let error = tutor.errorMessage {
                Text(error)
                    .font(.appBody(size: 13))
                    .foregroundStyle(Theme.danger)
                    .lineLimit(1)
                    .frame(maxWidth: 110)
            }
        }
    }

    private var speakerButton: some View {
        Button {
            if tutor.status == .connected {
                tutor.isMuted.toggle()
            } else if tutor.status == .idle || tutor.status == .error {
                tutor.connect()
            }
        } label: {
            Group {
                if tutor.status == .connecting {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.accent)
                } else {
                    Image(systemName: speakerIcon)
                        .font(.system(size: 17, weight: .medium))
                }
            }
            .foregroundStyle(speakerTint)
            .frame(width: 44, height: 36)
            .background(speakerFill, in: .capsule)
            .background {
                if tutor.isSpeaking && !tutor.isMuted {
                    Capsule()
                        .fill(Theme.accent.opacity(0.3))
                        .modifier(PulseEffect())
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(tutor.status == .connecting)
        .accessibilityLabel(speakerAccessibilityLabel)
    }

    private var speakerAccessibilityLabel: String {
        switch tutor.status {
        case .connected: tutor.isMuted ? "Unmute voice tutor" : "Mute voice tutor"
        case .connecting: "Connecting voice tutor"
        default: "Start voice tutor"
        }
    }

    private var speakerLabel: String {
        switch tutor.status {
        case .connected: tutor.isMuted ? "Muted" : "Live"
        case .connecting: "…"
        default: "Gemini"
        }
    }

    private var speakerIcon: String {
        switch tutor.status {
        case .error: "speaker.slash"
        default: tutor.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        }
    }

    private var speakerFill: Color {
        switch tutor.status {
        case .connecting: Theme.accent.opacity(0.2)
        case .error: Theme.danger.opacity(0.1)
        default: tutor.isMuted ? Theme.stateHover : Theme.accent.opacity(0.15)
        }
    }

    private var speakerTint: Color {
        switch tutor.status {
        case .error: Theme.danger
        default: tutor.isMuted ? Theme.textTertiary : Theme.accent
        }
    }

    private var micPill: some View {
        Button {
            tutor.toggleMic()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tutor.isMicOpen ? "mic.fill" : "mic.slash")
                    .font(.system(size: 17, weight: .medium))
                Text("Ask")
                    .font(.appBody(size: 15, weight: .medium))
            }
            .foregroundStyle(tutor.isMicOpen ? Color.red : Theme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(tutor.isMicOpen ? Color.red.opacity(0.12) : .clear, in: .capsule)
            .overlay {
                if tutor.isMicOpen {
                    Capsule()
                        .stroke(Color.red.opacity(0.4), lineWidth: 1.5)
                        .modifier(PulseEffect())
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tutor.isMicOpen ? "Stop asking" : "Ask a question")
    }
}

/// Continuous soft pulse used for the speaking ring and live mic border.
private struct PulseEffect: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? 1.35 : 1)
            .opacity(pulsing ? 0 : 0.9)
            .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: pulsing)
            .onAppear { pulsing = true }
    }
}
