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
    @State private var imageGenerator = CardImageGenerator()

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
            // Header: label, writing indicator, progress
            HStack(spacing: 10) {
                Text("LECTURE NOTES")
                    .font(.appBody(size: 13, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if isStreaming && !isLastCard {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Theme.accentGradient)
                            .frame(width: 6, height: 6)
                        Text("Writing")
                            .font(.appBody(size: 13))
                            .foregroundStyle(Theme.accentGradient)
                    }
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

            // Card pages — a native paged TabView so swipes track the finger
            // and Back/Next slide between cards.
            TabView(selection: Binding(
                get: { safeIndex },
                set: { currentIndex = $0 }
            )) {
                ForEach(cards.indices, id: \.self) { index in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            // AI-generated illustration (Nano Banana Flash Lite)
                            CardIllustrationView(
                                image: imageGenerator.images[index],
                                isGenerating: imageGenerator.generating.contains(index)
                            )

                            MarkdownText(content: cards[index])
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 20)
                        .animation(.easeOut(duration: 0.3), value: imageGenerator.images[index] != nil)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Page dots (above the navigation bar)
            if cards.count > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<cards.count, id: \.self) { index in
                        Capsule()
                            .fill(index == safeIndex ? Theme.accent : Theme.borderSubtle)
                            .frame(width: index == safeIndex ? 14 : 5, height: 5)
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    currentIndex = index
                                }
                            }
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 4)
            }

            // Floating liquid-glass navigation bar at the card's bottom edge —
            // one shared glass capsule holding all controls (podchat player style).
            HStack {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        currentIndex = max(0, safeIndex - 1)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isFirstCard)
                .opacity(isFirstCard ? 0.4 : 1)

                Spacer()

                // Voice tutor controls (Gemini Live + Ask Question)
                if let tutor = model.voiceTutor {
                    VoiceControlBar(tutor: tutor)
                }

                Spacer()

                if isLastCard && showQuizButton {
                    Button(action: onQuizMe) {
                        HStack(spacing: 4) {
                            Text("Quiz")
                                .font(.appBody(size: 17, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Theme.accentGradient, in: .capsule)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) {
                            currentIndex = min(cards.count - 1, safeIndex + 1)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLastCard)
                    .opacity(isLastCard ? 0.4 : 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        // Feed the voice tutor: all cards as context, the visible card to
        // read aloud (kickoff on first, then on each flip).
        .onAppear {
            model.voiceTutorCardsChanged(all: cards, current: cards[safeIndex])
            // Generate illustrations for saved lectures (not streaming)
            if !isStreaming {
                imageGenerator.generateImages(for: cards)
            }
        }
        .onChange(of: safeIndex) {
            model.voiceTutorCardsChanged(all: cards, current: cards[min(currentIndex, cards.count - 1)])
        }
        .onChange(of: cards.count) {
            model.voiceTutorCardsChanged(all: cards, current: cards[min(currentIndex, cards.count - 1)])
        }
        .onChange(of: isStreaming) {
            // Kick off image generation once the lecture finishes streaming
            if !isStreaming {
                imageGenerator.generateImages(for: cards)
            }
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
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .scaleEffect(1.4)
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
