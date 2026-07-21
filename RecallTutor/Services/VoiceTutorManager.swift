import Foundation
import Observation

/// Orchestrates one realtime voice-tutor session for the current lecture —
/// the iOS counterpart of the web app's voice overlays. Owns the session,
/// mic recorder, and player; feeds cards and quiz events into the model.
///
/// Supports three backends (mirroring podchat's VoiceModeViewModel):
/// - **Raw WebSocket** (`GeminiLiveSession`): when the user has a Gemini API
///   key, connects directly to `gemini-3.1-flash-live-preview`.
/// - **OpenAI Realtime** (`OpenAIRealtimeSession`): when OpenAI is selected
///   or it is the only personal voice key, connects to `gpt-realtime-2.1`.
/// - **Firebase AI SDK** (`FirebaseLiveBackend`): when no key is configured,
///   uses Firebase AI's native Live API with `gemini-2.5-flash-native-audio`
///   — no API key required, Firebase handles auth via GoogleService-Info.plist.
@Observable
@MainActor
final class VoiceTutorManager {
    let topic: String
    let readingLevel: ReadingLevel
    private let preferredProvider: AIProvider
    // Chosen once per lecture so reconnects keep the same voice.
    private let sessionVoice: String

    private(set) var status: LiveSessionStatus = .idle {
        didSet {
            // A card change that arrives while still connecting (common on
            // the slower Firebase backend) used to be silently dropped by
            // updateCards' guard below, with nothing to retry it once the
            // connection completed — the tutor would just stay silent until
            // the next flip. Replay whatever was last requested as soon as
            // we're actually connected.
            guard status == .connected, oldValue != .connected,
                  let pending = pendingCardUpdate else { return }
            pendingCardUpdate = nil
            updateCards(all: pending.all, current: pending.current)
        }
    }
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

    // MARK: - Backend selection

    /// Which backend is currently active.
    enum LiveBackend {
        case geminiWebSocket
        case openAIWebSocket
        case firebase   // Firebase AI SDK → gemini-2.5-flash-native-audio
    }

    /// The currently active backend (nil when disconnected).
    private(set) var activeBackend: LiveBackend?

    private var hasGeminiAPIKey: Bool { Keychain.loadKey(.gemini) != nil }
    private var hasOpenAIAPIKey: Bool { Keychain.loadKey(.openai) != nil }

    // MARK: - Services

    private var session: GeminiLiveSession?
    private var openAISession: OpenAIRealtimeSession?
    private let fbBackend = FirebaseLiveBackend()
    private var recorder: LiveAudioRecorder?
    private var player: LiveAudioPlayer?
    // When the mic was opened — playback that starts within a moment of this
    // is leftover audio from the turn the student just barged in on, not a
    // reply, and must not trigger the auto mic close.
    private var micOpenedAt = Date.distantPast

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
    // The most recent updateCards(all:current:) call received while not yet
    // .connected — replayed once the connection completes (see status'
    // didSet) instead of being silently dropped.
    private var pendingCardUpdate: (all: [String], current: String?)?
    // Pause tutor audio from the moment the quiz opens until its first
    // question is injected — the model is usually mid-turn on a card
    // explanation, and its remaining chunks would talk over the quiz intro.
    private var suppressAudio = false

    init(topic: String, readingLevel: ReadingLevel, provider: AIProvider) {
        self.topic = topic
        self.readingLevel = readingLevel
        self.preferredProvider = provider
        self.sessionVoice = LiveTutorPrompts.voice(topic: topic, level: readingLevel)
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
        openAISession?.disconnect()
        openAISession = nil
        fbBackend.disconnect()
        closeMic()
        player?.stop()

        LiveAudioSession.activate()

        let player = LiveAudioPlayer()
        player.muted = isMuted
        // Gemini's raw WebSocket voice benefits from a small makeup gain.
        // OpenAI Realtime and Firebase output are already normalized.
        player.gain = hasGeminiAPIKey && preferredProvider != .openai ? 1.5 : 1.0
        player.onPlaybackStart = { [weak self] in
            guard let self else { return }
            if self.isMicOpen, Date().timeIntervalSince(self.micOpenedAt) > 1.0 {
                self.closeMic()
                self.backendSendAudioStreamEnd()
            }
            if !self.isMuted { self.isSpeaking = true }
        }
        player.onPlaybackEnd = { [weak self] in
            self?.isSpeaking = false
        }
        self.player = player

        let systemInstr = LiveTutorPrompts.buildSystemInstruction(topic: topic, level: readingLevel)

        if preferredProvider == .openai, hasOpenAIAPIKey {
            activeBackend = .openAIWebSocket
            connectOpenAI(systemInstruction: systemInstr)
        } else if hasGeminiAPIKey {
            // Use raw WebSocket → gemini-3.1-flash-live-preview (best quality).
            activeBackend = .geminiWebSocket
            connectWebSocket(systemInstruction: systemInstr)
        } else if hasOpenAIAPIKey {
            activeBackend = .openAIWebSocket
            connectOpenAI(systemInstruction: systemInstr)
        } else {
            // No API key → use Firebase AI SDK tier.
            // Requires sign-in (Firebase is account-bound).
            guard AuthManager.shared.isSignedIn else {
                errorMessage = "Sign in to use the voice tutor, or add a Gemini or OpenAI API key in Settings."
                return
            }
            guard FirebaseAIClient.isAvailable else {
                errorMessage = "Firebase isn't set up. Add GoogleService-Info.plist (see FIREBASE.md)."
                return
            }

            activeBackend = .firebase
            connectFirebase(systemInstruction: systemInstr)
        }
    }

    private func connectWebSocket(systemInstruction: String) {
        let session = GeminiLiveSession(callbacks: GeminiLiveCallbacks(
            onStatusChange: { [weak self] status in
                guard let self else { return }
                self.status = status
                if status == .error { self.isSpeaking = false }
                if status != .connected {
                    if self.isMicOpen {
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
            systemInstruction: systemInstruction,
            voice: sessionVoice
        )
    }

    private func connectOpenAI(systemInstruction: String) {
        let session = OpenAIRealtimeSession(callbacks: OpenAIRealtimeCallbacks(
            onStatusChange: { [weak self] status in
                guard let self else { return }
                self.status = status
                if status == .error { self.isSpeaking = false }
                if status != .connected {
                    if self.isMicOpen { self.errorMessage = "Connection dropped — ask again" }
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
                self?.player?.flush()
            },
            onError: { [weak self] message in
                self?.errorMessage = message
            }
        ))
        self.openAISession = session

        hasKickedOff = false
        sentCards.removeAll()
        readCards.removeAll()
        lastSpokenCard = nil
        sentQuiz = nil
        sentAnswer = nil
        sentQuizResult = nil

        session.connect(instructions: systemInstruction, voice: "marin")
    }

    private func connectFirebase(systemInstruction: String) {
        fbBackend.voice = sessionVoice
        fbBackend.systemInstruction = systemInstruction

        fbBackend.onStatusChange = { [weak self] status in
            guard let self else { return }
            self.status = status
            if status == .error { self.isSpeaking = false }
            if status != .connected {
                if self.isMicOpen {
                    self.errorMessage = "Connection dropped — ask again"
                }
                self.closeMic()
            }
        }
        fbBackend.onAudioChunk = { [weak self] data in
            guard let self, !self.suppressAudio else { return }
            self.player?.playChunkData(data)
        }
        fbBackend.onAudioTurnStarted = { [weak self] in
            guard let self else { return }
            if self.isMicOpen, Date().timeIntervalSince(self.micOpenedAt) > 1.0 {
                self.closeMic()
            }
            if !self.isMuted { self.isSpeaking = true }
        }
        fbBackend.onInterrupted = { [weak self] in
            self?.player?.flush()
        }
        fbBackend.onError = { [weak self] message in
            self?.errorMessage = message
        }

        hasKickedOff = false
        sentCards.removeAll()
        readCards.removeAll()
        lastSpokenCard = nil
        sentQuiz = nil
        sentAnswer = nil
        sentQuizResult = nil

        fbBackend.connect()
    }

    func disconnect() {
        session?.disconnect()
        session = nil
        openAISession?.disconnect()
        openAISession = nil
        fbBackend.disconnect()
        activeBackend = nil
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
        pendingCardUpdate = nil
        status = .idle
        isSpeaking = false
        LiveAudioSession.deactivate()
    }

    // MARK: - Unified send helpers

    /// Send context (no model response) to whichever backend is active.
    private func backendSendContext(_ text: String) {
        switch activeBackend {
        case .geminiWebSocket: session?.sendContext(text)
        case .openAIWebSocket: openAISession?.sendContext(text)
        case .firebase: fbBackend.sendContext(text)
        case nil: break
        }
    }

    /// Send text that triggers a model response to whichever backend is active.
    private func backendSendText(_ text: String) {
        switch activeBackend {
        case .geminiWebSocket: session?.sendText(text)
        case .openAIWebSocket: openAISession?.sendText(text)
        case .firebase: fbBackend.sendText(text)
        case nil: break
        }
    }

    /// Send audio to whichever backend is active.
    private func backendSendAudio(_ base64: String) {
        switch activeBackend {
        case .geminiWebSocket: session?.sendAudio(base64)
        case .openAIWebSocket: openAISession?.sendAudio(base64)
        case .firebase: fbBackend.sendAudio(base64Data: base64)
        case nil: break
        }
    }

    private func backendSendAudioStreamEnd() {
        switch activeBackend {
        case .geminiWebSocket: session?.sendAudioStreamEnd()
        case .openAIWebSocket: openAISession?.sendAudioStreamEnd()
        case .firebase, nil: break
        }
    }

    private func backendInterruptResponse() {
        if activeBackend == .openAIWebSocket {
            openAISession?.cancelResponse()
        }
    }

    // MARK: - Card feed

    /// Called whenever the visible card or the card list changes. Seeds new
    /// cards as context (pre-kickoff only — Gemini Live ignores clientContent
    /// seeding once the conversation starts), and reads the visible card
    /// aloud on the first show and on each flip.
    func updateCards(all: [String], current: String?) {
        guard status == .connected else {
            pendingCardUpdate = (all, current)
            return
        }

        if !hasKickedOff {
            for (index, card) in all.enumerated() where !sentCards.contains(card) {
                sentCards.insert(card)
                backendSendContext("[CARD \(index + 1) CONTENT]\n\(card)")
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
                    self.backendSendText(
                        "[RECONNECTED MID-LECTURE — CURRENT CARD]\n\(current)\n\nThe voice connection dropped and was just restored partway through this lecture. Pick up naturally from this card — do NOT re-introduce the topic, greet me, or start over. Briefly continue explaining this card's content."
                    )
                } else {
                    self.backendSendText(
                        "[FIRST CARD]\n\(current)\n\nBegin now. Start by giving a brief, enthusiastic introduction to the topic, then explain the content of this first card. Keep it conversational and engaging. Do NOT greet me or say hello."
                    )
                }
            }
        } else {
            // Cut off the previous card's audio so the tutor tracks the flip
            // immediately instead of queueing behind stale speech.
            player?.flush()
            if isRevisit {
                backendSendText(
                    "[CURRENT CARD — the student flipped back to this card]\n\(current)\n\nThe student returned to this card to review it. Briefly recap its key point in a fresh way — one or two sentences, don't repeat your earlier explanation word for word."
                )
            } else {
                backendSendText(
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
        guard status == .connected, sentQuiz != context else { return }
        sentQuiz = context
        sentAnswer = nil
        // The quiz has actually started — lift the intro suppression and drop
        // any stale buffered speech so the tutor comes back on the question.
        suppressAudio = false
        player?.flush()
        backendSendText(
            "[QUIZ QUESTION]\n\(context)\n\nA quiz question has appeared! Read it out loud engagingly and let the student think about the answer. Do not reveal the correct answer."
        )
    }

    func answerGiven(_ context: String) {
        guard status == .connected, sentAnswer != context else { return }
        sentAnswer = context
        player?.flush()
        backendSendText(
            "\(context)\n\nReact to how the student answered. Be concise — one or two sentences. Be encouraging if correct, gently corrective if wrong. Then stop and wait for the next question."
        )
    }

    func quizFinished(_ context: String) {
        guard status == .connected, sentQuizResult != context else { return }
        sentQuizResult = context
        player?.flush()
        backendSendText(
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
            backendSendAudioStreamEnd()
        } else {
            Task { [weak self] in
                guard await LiveAudioRecorder.requestPermission() else {
                    self?.errorMessage = "Microphone access denied"
                    return
                }
                guard let self, self.status == .connected else { return }
                do {
                    let recorder = LiveAudioRecorder(sampleRate: self.activeBackend == .openAIWebSocket ? 24_000 : 16_000)
                    try recorder.start { [weak self] base64 in
                        Task { @MainActor in
                            self?.backendSendAudio(base64)
                        }
                    }
                    self.recorder = recorder
                    self.errorMessage = nil
                    self.isMicOpen = true
                    self.micOpenedAt = Date()
                    // Opening the mic is an explicit "my turn" — stop the
                    // tutor's speech so it isn't talking into the open mic,
                    // and duck any reply audio while the mic stays open.
                    self.player?.flush()
                    self.backendInterruptResponse()
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
