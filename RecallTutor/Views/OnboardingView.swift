import SwiftUI

/// First-launch onboarding walkthrough — introduces Recall Tutor's features
/// across a few swipeable pages, then invites the user to get started.
/// Modeled after podchat's OnboardingView with Recall Tutor's warm sunset theme.
struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool

    @State private var currentPage = 0

    private let pages: [(icon: String, title: String, subtitle: String, color: Color)] = [
        (
            icon: "graduationcap.fill",
            title: "Learn Anything",
            subtitle: "Pick a topic and get a bite-sized lecture with clear visual cards — powered by AI that adapts to your reading level."
        ,
            color: Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255) // orange-500
        ),
        (
            icon: "brain.head.profile.fill",
            title: "Test Your Recall",
            subtitle: "After each lecture, take a quiz to lock in what you learned. Questions target real understanding, not rote memorization."
        ,
            color: Color(red: 234 / 255, green: 88 / 255, blue: 12 / 255)  // orange-600
        ),
        (
            icon: "speaker.wave.2.fill",
            title: "Voice Tutor",
            subtitle: "Turn on the voice tutor for a conversational learning experience. Ask questions, get explanations — like a personal professor."
        ,
            color: Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)  // red-600
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    onboardingPage(page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentPage)

            bottomSection
                .padding(.bottom, 40)
                .padding(.horizontal, 32)
        }
        .background(
            LinearGradient(
                colors: [Theme.page, pages[currentPage].color.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: currentPage)
        )
    }

    // MARK: - Page content

    private func onboardingPage(_ page: (icon: String, title: String, subtitle: String, color: Color)) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(page.color.opacity(0.08))
                    .frame(width: 180, height: 180)
                Circle()
                    .fill(page.color.opacity(0.14))
                    .frame(width: 140, height: 140)
                Image(systemName: page.icon)
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(page.color)
            }

            Text(page.title)
                .font(.serifDisplay(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text(page.subtitle)
                .font(.appBody(size: 17))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Bottom: dots + action

    private var bottomSection: some View {
        VStack(spacing: 20) {
            // Page indicator dots
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? pages[currentPage].color : Theme.textTertiary.opacity(0.3))
                        .frame(width: index == currentPage ? 10 : 7, height: index == currentPage ? 10 : 7)
                        .animation(.easeInOut(duration: 0.2), value: currentPage)
                }
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if currentPage < pages.count - 1 {
                    currentPage += 1
                } else {
                    finishOnboarding()
                }
            } label: {
                Text(currentPage == pages.count - 1 ? "Get Started" : "Next")
                    .font(.appBody(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.accentGradient, in: .capsule)
            }
            .buttonStyle(.plain)

            if currentPage < pages.count - 1 {
                Button {
                    finishOnboarding()
                } label: {
                    Text("Skip")
                        .font(.appBody(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func finishOnboarding() {
        withAnimation(.easeInOut(duration: 0.3)) {
            UserDefaults.standard.set(true, forKey: "recalltutor_has_completed_onboarding")
            hasCompletedOnboarding = true
        }
    }
}
