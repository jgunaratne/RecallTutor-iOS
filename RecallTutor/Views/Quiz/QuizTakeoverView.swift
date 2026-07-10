import SwiftUI

/// Full-screen pop-quiz takeover — port of components/QuizTakeover.tsx.
/// Phases: intro → question (fuse timer) → reveal (streamed feedback) →
/// next … → scorecard.
struct QuizTakeoverView: View {
    let question: String
    let cards: [String]

    @Environment(ChatModel.self) private var model

    private enum Phase {
        case intro, question, reveal, scorecard
    }

    private static let questionsPerRound = 5
    private static let timerDuration: TimeInterval = 45
    private static let difficulties: [QuizDifficulty] = [.warmup, .warmup, .solid, .solid, .tricky]

    @State private var phase: Phase = .intro
    @State private var currentQuestion: QuizQuestion?
    @State private var questionIndex = 0
    @State private var score = 0
    @State private var streak = 0
    @State private var chosenIndex: Int?
    @State private var feedback = ""
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var questionStartedAt = Date()
    @State private var prefetchedQuestion: QuizQuestion?
    @State private var generatedQuestions: [String] = []
    @State private var introLine = Prompts.professorIntroLines.randomElement()!
    @State private var feedbackTask: Task<Void, Never>?
    @State private var timerExpired = false

    var body: some View {
        ZStack {
            Theme.page.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 16) {
                        switch phase {
                        case .intro: introView
                        case .question: questionView
                        case .reveal: revealView
                        case .scorecard: scorecardView
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                }

                if phase == .reveal {
                    nextButton
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }

            if isLoading && phase != .intro {
                Theme.page.opacity(0.85).ignoresSafeArea()
                loadingRow("Loading…")
            }
        }
        .task { await startAfterIntro() }
        // Pause the voice tutor while the quiz intro shows — the model is
        // usually mid-turn on a card explanation; the first question lifts it.
        .onAppear { model.voiceTutor?.quizStateChanged(isActive: true) }
    }

    /// Surface each question to the voice tutor as it appears. The answer
    /// options are included, but not which one is correct — the tutor should
    /// build suspense, not blurt the answer.
    private func notifyTutorOfQuestion(_ q: QuizQuestion) {
        let letters = ["A", "B", "C", "D"]
        let context = (
            ["Question \(questionIndex + 1) of \(Self.questionsPerRound) (difficulty: \(q.difficulty.rawValue)):", q.question]
            + q.answers.enumerated().map { "\(letters[min($0.offset, 3)]). \($0.element.text)" }
        ).joined(separator: "\n")
        model.voiceTutor?.quizQuestionShown(context)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Pop Quiz")
                .font(.serifDisplay(size: 22))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            // The voice tutor's controls teleport here while the quiz is open
            // so the student can mute the tutor or ask a question mid-quiz.
            if let tutor = model.voiceTutor {
                VoiceControlBar(tutor: tutor)
            }
            if phase != .scorecard {
                Text("Question \(questionIndex + 1) of \(Self.questionsPerRound)")
                    .font(.appBody(size: 17))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            Button {
                feedbackTask?.cancel()
                model.dismissQuiz()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close quiz")
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    // MARK: - Intro

    private var introView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 100)
            Text("Pop Quiz")
                .font(.serifDisplay(size: 22, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Text("“\(introLine)”")
                .font(.appBody(size: 17))
                .italic()
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: 320)
            if isLoading {
                loadingRow("Writing a quiz for you…")
            }
            if let loadError {
                VStack(spacing: 12) {
                    Text(loadError)
                        .font(.appBody(size: 17))
                        .foregroundStyle(Theme.danger)
                    Button("Try again") {
                        Task { await startQuiz() }
                    }
                    .font(.appBody(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accentStrong)
                }
            }
        }
    }

    private func loadingRow(_ label: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(Theme.accent)
            Text(label)
                .font(.appBody(size: 17))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Question phase

    @ViewBuilder
    private var questionView: some View {
        if let q = currentQuestion {
            VStack(spacing: 18) {
                FuseTimerView(duration: Self.timerDuration, isPaused: false, startedAt: questionStartedAt) {
                    handleTimerExpiry()
                }

                Text("“\(q.hostIntro)”")
                    .font(.appBody(size: 17))
                    .italic()
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)

                Text(q.question)
                    .font(.serifDisplay(size: 22))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)

                difficultyBadge(q.difficulty)

                Spacer(minLength: 16)

                VStack(spacing: 10) {
                    ForEach(Array(q.answers.enumerated()), id: \.offset) { index, answer in
                        AnswerButtonView(
                            text: answer.text,
                            index: index,
                            state: .idle
                        ) {
                            handleAnswer(index)
                        }
                    }
                }
            }
        }
    }

    private func difficultyBadge(_ difficulty: QuizDifficulty) -> some View {
        let (fill, text): (Color, Color) = switch difficulty {
        case .warmup: (Theme.emeraldFill, Theme.correctText)
        case .solid: (Theme.amberFill, Theme.amberText)
        case .tricky: (Theme.roseFill, Theme.wrongText)
        }
        return Text(difficulty.label)
            .font(.appBody(size: 13, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(fill)
            .clipShape(Capsule())
    }

    // MARK: - Reveal phase

    @ViewBuilder
    private var revealView: some View {
        if let q = currentQuestion {
            VStack(spacing: 14) {
                Text(q.question)
                    .font(.serifDisplay(size: 17))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    ForEach(Array(q.answers.enumerated()), id: \.offset) { index, answer in
                        AnswerButtonView(
                            text: answer.text,
                            index: index,
                            state: answer.isCorrect
                                ? .revealedCorrect
                                : (index == chosenIndex ? .revealedWrong : .revealedDimmed)
                        ) {}
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("FEEDBACK")
                        .font(.appBody(size: 13, weight: .medium))
                        .tracking(0.5)
                        .foregroundStyle(Theme.textTertiary)
                    if feedback.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                            Text("…").foregroundStyle(Theme.textTertiary)
                        }
                    } else {
                        Text(feedback)
                            .font(.appBody(size: 17))
                            .italic()
                            .lineSpacing(5)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.035), radius: 10, y: 4)
            }
        }
    }

    private var nextButton: some View {
        Button {
            Task { await handleNext() }
        } label: {
            Text(questionIndex < Self.questionsPerRound - 1 ? "Next question" : "See results")
                .font(.appBody(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accentStrong)
    }

    // MARK: - Scorecard phase

    private var scorecardView: some View {
        ScorecardView(
            score: score,
            total: Self.questionsPerRound,
            streak: streak,
            mastery: model.masteryNote?.after,
            previousLevel: model.masteryNote?.before,
            onReturnToHome: { model.closeQuizToHome() },
            onGoDeeper: { model.goDeeper() }
        )
        .padding(.top, 40)
    }

    // MARK: - Quiz flow

    private func startAfterIntro() async {
        try? await Task.sleep(for: .seconds(2))
        await startQuiz()
    }

    /// Build the per-question transcript: question i is grounded in card
    /// i (wrapping), so the quiz tests exactly what the cards taught.
    private func transcript(forQuestionAt index: Int) -> String {
        let cardIndex = cards.isEmpty ? 0 : index % cards.count
        let card = cards.indices.contains(cardIndex) ? cards[cardIndex] : ""
        return [
            "Student asked: \(question)",
            "",
            "Tutor's lecture notes (card \(cardIndex + 1) of \(cards.count)) — base the question ONLY on this content:",
            card,
        ].joined(separator: "\n")
    }

    private func fetchQuestion(at index: Int) async throws -> QuizQuestion {
        let q = try await AIService.generateQuizQuestion(
            provider: model.provider,
            transcript: transcript(forQuestionAt: index),
            difficulty: Self.difficulties[index],
            readingLevel: model.readingLevel,
            previousQuestions: generatedQuestions
        )
        generatedQuestions.append(q.question)
        return q
    }

    private func startQuiz() async {
        isLoading = true
        loadError = nil
        do {
            generatedQuestions = []
            let first = try await fetchQuestion(at: 0)
            currentQuestion = first
            phase = .question
            questionStartedAt = Date()
            notifyTutorOfQuestion(first)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func handleTimerExpiry() {
        guard let q = currentQuestion, chosenIndex == nil else { return }
        // Treat as incorrect: pick a wrong answer on the student's behalf.
        let correctIndex = q.answers.firstIndex(where: \.isCorrect) ?? 0
        handleAnswer(correctIndex == 0 ? 1 : 0)
    }

    private func handleAnswer(_ index: Int) {
        guard let q = currentQuestion, chosenIndex == nil else { return }
        let responseTime = Date().timeIntervalSince(questionStartedAt)
        chosenIndex = index

        let chosen = q.answers[index]
        let correct = q.answers.first(where: \.isCorrect)!
        let wasCorrect = chosen.isCorrect

        if wasCorrect {
            score += 1
            streak += 1
        } else {
            streak = 0
        }

        // Tell the voice tutor how the student answered so it can react.
        model.voiceTutor?.answerGiven(
            [
                "[STUDENT ANSWERED — Question \(questionIndex + 1)]",
                "Question: \(q.question)",
                "Student chose: \(chosen.text)",
                wasCorrect
                    ? "That is CORRECT! 🎉"
                    : "That is INCORRECT. The correct answer was: \(correct.text)",
                "Response time: \(String(format: "%.1f", responseTime))s",
            ].joined(separator: "\n")
        )

        feedback = ""
        phase = .reveal

        // Pre-fetch the next question while the student reads feedback.
        let nextIndex = questionIndex + 1
        if nextIndex < Self.questionsPerRound {
            Task {
                prefetchedQuestion = try? await fetchQuestion(at: nextIndex)
            }
        }

        // Stream the feedback reaction.
        feedbackTask = Task {
            do {
                let stream = AIService.streamReaction(
                    provider: model.provider,
                    question: q.question,
                    chosen: chosen,
                    correct: correct,
                    wasCorrect: wasCorrect,
                    streak: wasCorrect ? streak : 0,
                    responseTimeSeconds: responseTime
                )
                for try await text in stream {
                    if Task.isCancelled { return }
                    feedback += text
                }
            } catch {
                if !Task.isCancelled && feedback.isEmpty {
                    feedback = wasCorrect
                        ? "Correct — well done."
                        : "Not quite. The correct answer was: \(correct.text)."
                }
            }
        }
    }

    private func handleNext() async {
        let nextIndex = questionIndex + 1
        feedbackTask?.cancel()

        if nextIndex >= Self.questionsPerRound {
            model.recordQuizCompletion(score: score, total: Self.questionsPerRound)
            model.voiceTutor?.quizFinished(
                [
                    "[QUIZ COMPLETE]",
                    "The quiz is over. Final score: \(score) out of \(Self.questionsPerRound).",
                    streak > 1 ? "The student finished on a \(streak)-question streak." : "",
                ]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            )
            phase = .scorecard
            return
        }

        chosenIndex = nil
        feedback = ""
        questionIndex = nextIndex

        if let prefetched = prefetchedQuestion {
            currentQuestion = prefetched
            prefetchedQuestion = nil
            phase = .question
            questionStartedAt = Date()
            notifyTutorOfQuestion(prefetched)
        } else {
            isLoading = true
            loadError = nil
            do {
                let q = try await fetchQuestion(at: nextIndex)
                currentQuestion = q
                phase = .question
                questionStartedAt = Date()
                notifyTutorOfQuestion(q)
            } catch {
                loadError = "Failed to load next question. Try again."
            }
            isLoading = false
        }
    }
}
