import SwiftUI

/// Length + quality options shown before kicking off a lecture video.
///
/// Presented as a centered modal card rather than an action sheet: the
/// fast-generation switch needs to sit alongside the length choice, and
/// `confirmationDialog` can only hold buttons.
struct VideoOptionsDialog: View {
    let cards: [String]
    /// Called with the chosen length and whether to skip frame chaining.
    let onGenerate: (VideoService.ClipLength, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    // Defaults on: the ~3× quicker render is the better trade for most
    // lectures, and the cost is visible cuts between scenes rather than a
    // continuous flow.
    @AppStorage("recalltutor_video_fast_generation") private var fastGeneration = true

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            card
                .padding(.horizontal, 32)
        }
        // fullScreenCover is opaque by default, which would hide the
        // lecture behind it instead of dimming it.
        .presentationBackground(.clear)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Create video")
                    .font(.serifDisplay(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Generate an instructional video. This will take a few minutes.")
                    .font(.appBody(size: 17))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $fastGeneration) {
                Text("Enable fast generation (less video consistency)")
                    .font(.appBody(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(Theme.accent)

            Divider().overlay(Theme.borderSoft)

            VStack(spacing: 10) {
                ForEach(VideoService.ClipLength.allCases) { length in
                    let cached = VideoService.hasCachedVideo(
                        for: cards, length: length, fastGeneration: fastGeneration
                    )
                    Button {
                        dismiss()
                        onGenerate(length, fastGeneration)
                    } label: {
                        HStack {
                            Text(length.label)
                            if cached {
                                Spacer()
                                Text("Ready to play")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Theme.textPrimary)
                }
            }

            Button("Cancel") { dismiss() }
                .buttonStyle(.borderless)
                .tint(Theme.textSecondary)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .background(Theme.page, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 24, y: 8)
    }
}
