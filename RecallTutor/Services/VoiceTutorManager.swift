import Foundation
import Observation

/// Orchestrates one Gemini Live voice-tutor session for the current lecture —
/// the iOS counterpart of components/GeminiLiveOverlay.tsx. Owns the session,
/// mic recorder, and player; feeds cards and quiz events into the model.
@Observable
@MainActor
final class VoiceTutorManager {
    let topic: String
    let readingLevel: ReadingLevel

    private(set) var status: LiveSessionStatus = .idle
    private(set) var isMicOpen = false
    private(set) var isSpeaking = false
    private(set) var errorMessage: String?
    var isMuted = false {
        didSet {
            player?.muted = isMuted
            if isMuted {
                // Flush pending audio but keep the session alive.
                player?.flush()
                isSpeaking = false
            }
        }
    }

    private var session: GeminiLiveSession?
    private var recorder: LiveAudioRecorder?
    private var player: LiveAudioPlayer?

    // Cards streamed to the model as grounding context vs. cards the tutor
    // has been asked to read aloud — separate sets, because every card
    // becomes context as it streams in, but reading happens only when the
    // student flips to it.
    private var sentCards = Set<String>()
    private var readCards = Set<String>()
    // The card most recently spoken about — dedupes repeat updateCards calls
    // for the same visible card (e.g. when the card list grows underneath it)
    // while still letting a card be spoken again on every return flip.
    private var lastSpokenCard: String?
    private var hasKickedOff = false
    // Survives reconnects (unlike hasKickedOff): a session rebuilt after an
    // error should resume the lecture, not re-run the topic introduction.
    private var hasIntroduced = false
    private var sentQuiz: String?
    private var sentAnswer: String?
    private var sentQuizResult: String?
    // Pause tutor audio from the moment the quiz opens until its first
    // question is injected — the model is usually mid-turn on a card
    // explanation, and its remaining chunks would talk over the quiz intro.
    private var suppressAudio = false

    init(topic: String, readingLevel: ReadingLevel) {
        self.topic = topic
        self.readingLevel = readingLevel
    }

    // MARK: - Connection

    func connect() {
        guard status == .idle || status == .error else { return }
        errorMessage = nil

        // Reconnect-from-error: tear down the previous session and player
        // first, or each retry leaks a running audio engine and a session
        // whose callbacks still write into this manager.
        session?.disconnect()
        session = nil
        closeMic()
        player?.stop()

        LiveAudioSession.activate()

        let player = LiveAudioPlayer()
        player.muted = isMuted
        player.onPlaybackStart = { [weak self] in
            guard let self else { return }
            // Don't flip isSpeaking when muted — the icon should stay muted.
            if !self.isMuted { self.isSpeaking = true }
        }
        player.onPlaybackEnd = { [weak self] in
            self?.isSpeaking = false
        }
        self.player = player

        let session = GeminiLiveSession(callbacks: GeminiLiveCallbacks(
            onStatusChange: { [weak self] status in
                guard let self else { return }
                self.status = status
                if status == .error { self.isSpeaking = false }
                if status != .connected {
                    if self.isMicOpen {
                        // The connection dropped mid-question; the half-sent
                        // turn is lost, so tell the student to re-ask.
                        self.errorMessage = "Connection dropped — ask again"
                    }
                    self.closeMic()
                }
            },
            onAudioChunk: { [weak self] base64 in
                guard let self, !self.suppressAudio else { return }
                self.player?.playChunk(base64)
            },
            onTextChunk: nil,
            onTurnComplete: nil,
            onInterrupted: { [weak self] in
                // Barge-in: the student spoke over the tutor.
                self?.player?.flush()
            },
            onError: { [weak self] message in
                self?.errorMessage = message
            }
        ))
        self.session = session

        hasKickedOff = false
        sentCards.removeAll()
        readCards.removeAll()
        lastSpokenCard = nil
        sentQuiz = nil
        sentAnswer = nil
        sentQuizResult = nil

        session.connect(
            systemInstruction: LiveTutorPrompts.buildSystemInstruction(topic: topic, level: readingLevel),
            voice: LiveTutorPrompts.voice(for: readingLevel)
        )
    }

    func disconnect() {
        session?.disconnect()
        session = nil
        closeMic()
        player?.stop()
        player = nil
        sentCards.removeAll()
        readCards.removeAll()
        lastSpokenCard = nil
        sentQuiz = nil
        sentAnswer = nil
        sentQuizResult = nil
        hasKickedOff = false
        hasIntroduced = false
        status = .idle
        isSpeaking = false
        LiveAudioSession.deactivate()
    }

    // MARK: - Card feed

    /// Called whenever the visible card or the card list changes. Seeds new
    /// cards as context (pre-kickoff only — Gemini Live ignores clientContent
    /// seeding once the conversation starts), and reads the visible card
    /// aloud on the first show and on each flip.
    func updateCards(all: [String], current: String?) {
        guard let session, status == .connected else { return }

        if !hasKickedOff {
            for (index, card) in all.enumerated() where !sentCards.contains(card) {
                sentCards.insert(card)
                session.sendContext("[CARD \(index + 1) CONTENT]\n\(card)")
            }
        }

        guard let current, current != lastSpokenCard else { return }
        lastSpokenCard = current
        let isRevisit = readCards.contains(current)
        readCards.insert(current)
        sentCards.insert(current)

        if !hasKickedOff {
            hasKickedOff = true
            let resuming = hasIntroduced
            hasIntroduced = true
            // Small delay to let the seeded context settle.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.status == .connected else { return }
                if resuming {
                    self.session?.sendText(
                        "[RECONNECTED MID-LECTURE — CURRENT CARD]\n\(current)\n\nThe voice connection dropped and was just restored partway through this lecture. Pick up naturally from this card — do NOT re-introduce the topic, greet me, or start over. Briefly continue explaining this card's content."
                    )
                } else {
                    self.session?.sendText(
                        "[FIRST CARD]\n\(current)\n\nBegin now. Start by giving a brief, enthusiastic introduction to the topic, then explain the content of this first card. Keep it conversational and engaging. Do NOT greet me or say hello."
                    )
                }
            }
        } else {
            // Cut off the previous card's audio so the tutor tracks the flip
            // immediately instead of queueing behind stale speech.
            player?.flush()
            if isRevisit {
                session.sendText(
                    "[CURRENT CARD — the student flipped back to this card]\n\(current)\n\nThe student returned to this card to review it. Briefly recap its key point in a fresh way — one or two sentences, don't repeat your earlier explanation word for word."
                )
            } else {
                session.sendText(
                    "[CURRENT CARD — the student just flipped to this card]\n\(current)\n\nThe student just moved to this card. Explain its content naturally, building on what you've already covered. Keep it brief and conversational."
                )
            }
        }
    }

    // MARK: - Quiz feed

    func quizStateChanged(isActive: Bool) {
        if isActive {
            suppressAudio = true
            player?.flush()
            isSpeaking = false
        } else {
            // Quiz closed/dismissed — let card audio flow again.
            suppressAudio = false
        }
    }

    func quizQuestionShown(_ context: String) {
        guard let session, status == .connected, sentQuiz != context else { return }
        sentQuiz = context
        sentAnswer = nil
        // The quiz has actually started — lift the intro suppression and drop
        // any stale buffered speech so the tutor comes back on the question.
        suppressAudio = false
        player?.flush()
        session.sendText(
            "[QUIZ QUESTION]\n\(context)\n\nA quiz question has appeared! Read it out loud engagingly and let the student think about the answer. Do not reveal the correct answer."
        )
    }

    func answerGiven(_ context: String) {
        guard let session, status == .connected, sentAnswer != context else { return }
        sentAnswer = context
        player?.flush()
        session.sendText(
            "\(context)\n\nReact to how the student answered. Be concise — one or two sentences. Be encouraging if correct, gently corrective if wrong. Then stop and wait for the next question."
        )
    }

    func quizFinished(_ context: String) {
        guard let session, status == .connected, sentQuizResult != context else { return }
        sentQuizResult = context
        player?.flush()
        session.sendText(
            "\(context)\n\nThe quiz has ended and the student is looking at their scorecard. Give a short closing remark on their overall performance — celebrate a strong score, or be warm and encouraging about trying again if they struggled. Two sentences at most, then stop."
        )
    }

    // MARK: - Mic

    func toggleMic() {
        guard status == .connected else { return }
        if isMicOpen {
            closeMic()
            // Commit the user's turn — without this, VAD waits forever for
            // trailing silence that never arrives once the stream stops.
            session?.sendAudioStreamEnd()
        } else {
            Task { [weak self] in
                guard await LiveAudioRecorder.requestPermission() else {
                    self?.errorMessage = "Microphone access denied"
                    return
                }
                guard let self, self.status == .connected else { return }
                do {
                    let recorder = LiveAudioRecorder()
                    let session = self.session
                    try recorder.start { base64 in
                        Task { @MainActor in
                            session?.sendAudio(base64)
                        }
                    }
                    self.recorder = recorder
                    self.errorMessage = nil
                    self.isMicOpen = true
                    // Opening the mic is an explicit "my turn" — stop the
                    // tutor's speech so it isn't talking into the open mic,
                    // and duck any reply audio while the mic stays open.
                    self.player?.flush()
                    self.player?.ducked = true
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func closeMic() {
        recorder?.stop()
        recorder = nil
        isMicOpen = false
        player?.ducked = false
    }
}
