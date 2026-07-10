import SwiftUI

/// Final score card with the progress ring and topic-mastery panel —
/// port of components/Scorecard.tsx.
struct ScorecardView: View {
    let score: Int
    let total: Int
    let streak: Int
    let mastery: TopicMastery?
    let previousLevel: MasteryLevel?
    let onReturnToHome: () -> Void
    let onGoDeeper: () -> Void

    @State private var ringProgress: Double = 0

    private var ratio: Double { Double(score) / Double(total) }
    private var isPerfect: Bool { score == total }
    private var isZero: Bool { score == 0 }

    private var headline: String {
        if isPerfect { return "Excellent result" }
        if isZero { return "Conceptual gaps" }
        return ratio >= 0.6 ? "Solid performance" : "Developing understanding"
    }

    private var subline: String {
        if isPerfect { return "Great job! You have fully mastered these concepts." }
        if isZero { return "Reviewing the material and trying again is recommended." }
        return ratio >= 0.6
            ? "You got most of them. Ready for more advanced questions next time?"
            : "A good start, but there are a few core traps to watch out for."
    }

    private var ringColor: Color {
        isPerfect ? Theme.correctBorder : isZero ? Theme.danger : Theme.accent
    }

    var body: some View {
        VStack(spacing: 22) {
            // Score ring
            ZStack {
                Circle()
                    .stroke(Theme.borderSoft, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(score)/\(total)")
                        .font(.appBody(size: 22, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(Int((ratio * 100).rounded()))%")
                        .font(.appBody(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 128, height: 128)
            .onAppear {
                withAnimation(.easeOut(duration: 1)) { ringProgress = ratio }
            }

            VStack(spacing: 8) {
                Text(headline)
                    .font(.serifDisplay(size: 22))
                    .foregroundStyle(Theme.textPrimary)
                Text(subline)
                    .font(.appBody(size: 17))
                    .lineSpacing(5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
            }

            if streak > 0 {
                Text("Streak · \(streak) in a row")
                    .font(.appBody(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.amberText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Theme.amberFill)
                    .clipShape(Capsule())
            }

            if let mastery {
                masteryPanel(mastery)
            }

            VStack(spacing: 8) {
                Button(action: onGoDeeper) {
                    Text("Go deeper on this topic")
                        .font(.appBody(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accentStrong)
                Button(action: onReturnToHome) {
                    Text("Return to home")
                        .font(.appBody(size: 17, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.glass)
            }

            Text("Concepts you missed will resurface in later sessions.")
                .font(.appBody(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: 260)
        }
        .padding(28)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.035), radius: 14, y: 4)
        .frame(maxWidth: 400)
    }

    private func masteryPanel(_ mastery: TopicMastery) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TOPIC MASTERY")
                    .font(.appBody(size: 13, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                // Celebrate level-ups: "Learning → Developing"
                if let previousLevel, previousLevel != mastery.level, mastery.level > previousLevel {
                    Text("\(previousLevel.label) → \(mastery.level.label)")
                        .font(.appBody(size: 13, weight: .semibold))
                        .foregroundStyle(mastery.level.textColor)
                } else {
                    Text(mastery.level.label)
                        .font(.appBody(size: 13, weight: .semibold))
                        .foregroundStyle(mastery.level.textColor)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.borderSubtle)
                    Capsule()
                        .fill(mastery.level.fillColor)
                        .frame(width: geo.size.width * mastery.score)
                }
            }
            .frame(height: 6)

            Text(mastery.feedback)
                .font(.appBody(size: 13))
                .lineSpacing(4)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Theme.page.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.borderSoft)
        )
    }
}
