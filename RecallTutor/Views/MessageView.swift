import SwiftUI

/// Full-screen lecture pager — one card at a time filling the available
/// space, with Back/Next controls pinned to the bottom of the card
/// (the iPhone-first take on components/Message.tsx).
struct LectureView: View {
    let message: ChatMessage
    let isStreaming: Bool
    let showQuizButton: Bool
    let onQuizMe: () -> Void

    @Environment(ChatModel.self) private var model
    @State private var currentIndex = 0

    var body: some View {
        let cards = CardSplitter.splitIntoCards(message.content)

        Group {
            if cards.isEmpty {
                loadingCard
            } else {
                pager(cards: cards)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Pager

    private func pager(cards: [String]) -> some View {
        let safeIndex = min(currentIndex, cards.count - 1)
        let isFirstCard = safeIndex == 0
        let isLastCard = safeIndex == cards.count - 1

        return VStack(spacing: 0) {
            // Header: label, writing indicator, voice controls, progress
            HStack(spacing: 10) {
                Text("LECTURE NOTES")
                    .font(.appBody(size: 13, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if isStreaming && !isLastCard {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 6, height: 6)
                        Text("Writing")
                            .font(.appBody(size: 13))
                            .foregroundStyle(Theme.accent)
                    }
                }
                if let tutor = model.voiceTutor {
                    VoiceControlBar(tutor: tutor)
                }
                if cards.count > 1 {
                    Text("\(safeIndex + 1) of \(cards.count)")
                        .font(.appBody(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Current card content — fills the screen, scrolls if long
            ScrollView {
                MarkdownText(content: cards[safeIndex])
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
            }
            .id(safeIndex)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Floating glass navigation at the card's bottom edge
            GlassEffectContainer(spacing: 12) {
                HStack {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            currentIndex = max(0, safeIndex - 1)
                        }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.appBody(size: 17))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.interactive())
                    }
                    .disabled(isFirstCard)
                    .opacity(isFirstCard ? 0.4 : 1)

                    Spacer()

                    if cards.count > 1 {
                        HStack(spacing: 5) {
                            ForEach(0..<cards.count, id: \.self) { index in
                                Capsule()
                                    .fill(index == safeIndex ? Theme.accent : Theme.borderSubtle)
                                    .frame(width: index == safeIndex ? 14 : 5, height: 5)
                                    .onTapGesture {
                                        withAnimation(.easeOut(duration: 0.15)) {
                                            currentIndex = index
                                        }
                                    }
                            }
                        }
                    }

                    Spacer()

                    if isLastCard && showQuizButton {
                        Button(action: onQuizMe) {
                            HStack(spacing: 4) {
                                Text("Quiz me")
                                    .font(.appBody(size: 17, weight: .medium))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accentStrong)
                    } else {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                currentIndex = min(cards.count - 1, safeIndex + 1)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Next")
                                    .font(.appBody(size: 17))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.interactive())
                        }
                        .disabled(isLastCard)
                        .opacity(isLastCard ? 0.4 : 1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        // Swipe between cards
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    withAnimation(.easeOut(duration: 0.15)) {
                        if value.translation.width < -40 {
                            currentIndex = min(cards.count - 1, safeIndex + 1)
                        } else if value.translation.width > 40 {
                            currentIndex = max(0, safeIndex - 1)
                        }
                    }
                }
        )
        // Feed the voice tutor: all cards as context, the visible card to
        // read aloud (kickoff on first, then on each flip).
        .onAppear {
            model.voiceTutorCardsChanged(all: cards, current: cards[safeIndex])
        }
        .onChange(of: safeIndex) {
            model.voiceTutorCardsChanged(all: cards, current: cards[min(currentIndex, cards.count - 1)])
        }
        .onChange(of: cards.count) {
            model.voiceTutorCardsChanged(all: cards, current: cards[min(currentIndex, cards.count - 1)])
        }
    }

    // MARK: - Loading

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LECTURE NOTES")
                .font(.appBody(size: 13, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accent)
                Text("Preparing lecture notes…")
                    .font(.appBody(size: 17))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(16)
    }
}
