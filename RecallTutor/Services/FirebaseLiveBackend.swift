import FirebaseAI
import Foundation

/// Firebase AI SDK–based Live API backend for the voice tutor.
///
/// Uses `FirebaseAI.liveModel()` → `session.connect()` instead of a raw
/// WebSocket, so signed-in users can use the voice tutor without a personal
/// API key. Firebase handles authentication via GoogleService-Info.plist.
///
/// Audio format: sends PCM 16kHz Int16 (raw Data), receives inline audio Data
/// (PCM 24kHz Int16) from the model.
@Observable
@MainActor
final class FirebaseLiveBackend {

    // MARK: - Callbacks (mirror GeminiLiveSession's callback API)

    var onAudioChunk: (@MainActor (Data) -> Void)?
    var onError: (@MainActor (String) -> Void)?
    var onStatusChange: (@MainActor (LiveSessionStatus) -> Void)?
    var onAudioTurnStarted: (@MainActor () -> Void)?
    var onInterrupted: (@MainActor () -> Void)?

    // MARK: - State

    private(set) var status: LiveSessionStatus = .idle {
        didSet {
            if oldValue != status { onStatusChange?(status) }
        }
    }

    private var liveSession: LiveSession?
    private var receiveTask: Task<Void, Never>?
    private var connectionEpoch = 0
    private var audioTurnStartedForCurrentTurn = false

    // Reconnection state — exponential backoff with jitter.
    private var reconnectAttempts = 0
    private static let maxReconnectAttempts = 5
    private var reconnectTask: Task<Void, Never>?

    // Setup timeout — fail fast if connect() hangs.
    private var setupTimeoutTask: Task<Void, Never>?
    private static let setupTimeout: TimeInterval = 15

    /// The Firebase model name for Live API — uses 2.5 Flash native audio
    /// since 3.1 may not be available on Firebase yet.
    static let firebaseModelName = "gemini-2.5-flash-native-audio-preview-12-2025"

    /// The voice to use for audio responses.
    var voice: String = "Puck"

    /// System instruction sent during setup.
    var systemInstruction = ""

    // MARK: - Connect

    func connect() {
        guard status == .idle || status == .error else { return }
        connectionEpoch += 1
        let epoch = connectionEpoch
        status = .connecting
        setupTimeoutTask?.cancel()

        // Build the LiveGenerativeModel with voice + system instruction.
        let liveModel = FirebaseAI.firebaseAI(backend: .googleAI()).liveModel(
            modelName: Self.firebaseModelName,
            generationConfig: LiveGenerationConfig(
                responseModalities: [.audio],
                speech: SpeechConfig(voiceName: voice)
            ),
            systemInstruction: ModelContent(role: "system", parts: systemInstruction)
        )

        // Setup timeout — fail fast if the server never responds.
        setupTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.setupTimeout * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard epoch == self.connectionEpoch, self.status == .connecting else { return }
            self.cleanupSession()
            self.status = .error
            self.onError?("Couldn't start the voice session. Please try again.")
        }

        // Connect asynchronously.
        Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await liveModel.connect()
                guard epoch == self.connectionEpoch else {
                    await session.close()
                    return
                }
                self.setupTimeoutTask?.cancel()
                self.setupTimeoutTask = nil
                self.liveSession = session
                self.reconnectAttempts = 0
                self.status = .connected
                self.startReceiving(session: session, epoch: epoch)
            } catch {
                guard epoch == self.connectionEpoch else { return }
                self.setupTimeoutTask?.cancel()
                self.setupTimeoutTask = nil
                self.onError?(error.localizedDescription)
                self.status = .error
            }
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        connectionEpoch += 1
        reconnectTask?.cancel()
        reconnectTask = nil
        setupTimeoutTask?.cancel()
        setupTimeoutTask = nil
        reconnectAttempts = 0
        cleanupSession()
        status = .idle
    }

    // MARK: - Send

    func sendAudio(base64Data: String) {
        guard status == .connected, let session = liveSession else { return }
        guard let rawData = Data(base64Encoded: base64Data) else { return }
        Task {
            await session.sendAudioRealtime(rawData)
        }
    }

    func sendText(_ text: String) {
        guard status == .connected, let session = liveSession else { return }
        Task {
            await session.sendContent(text, turnComplete: true)
        }
    }

    /// Append context without triggering a model response.
    func sendContext(_ text: String) {
        guard status == .connected, let session = liveSession else { return }
        Task {
            await session.sendContent(text, turnComplete: false)
        }
    }

    // MARK: - Receive Loop

    private func startReceiving(session: LiveSession, epoch: Int) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await message in session.responses {
                    guard !Task.isCancelled, epoch == self.connectionEpoch else { break }
                    self.handleMessage(message)
                }
                guard !Task.isCancelled, epoch == self.connectionEpoch else { return }
                self.scheduleReconnect()
            } catch {
                guard !Task.isCancelled, epoch == self.connectionEpoch else { return }
                self.onError?(error.localizedDescription)
                self.scheduleReconnect()
            }
        }
    }

    private func handleMessage(_ message: LiveServerMessage) {
        switch message.payload {
        case .content(let content):
            handleContent(content)
        case .toolCall, .toolCallCancellation:
            break
        case .goingAwayNotice:
            scheduleReconnect()
        case .sessionResumptionUpdate:
            break
        @unknown default:
            break
        }
    }

    private func handleContent(_ content: LiveServerContent) {
        if let modelTurn = content.modelTurn {
            for part in modelTurn.parts {
                if let inlineData = part as? InlineDataPart,
                   inlineData.mimeType.hasPrefix("audio/") {
                    if !audioTurnStartedForCurrentTurn {
                        audioTurnStartedForCurrentTurn = true
                        onAudioTurnStarted?()
                    }
                    onAudioChunk?(inlineData.data)
                }
            }
        }

        if content.isTurnComplete {
            audioTurnStartedForCurrentTurn = false
        }

        if content.wasInterrupted {
            audioTurnStartedForCurrentTurn = false
            onInterrupted?()
        }
    }

    // MARK: - Reconnect (exponential backoff with jitter)

    private func scheduleReconnect() {
        guard status != .connecting else { return }
        guard reconnectAttempts < Self.maxReconnectAttempts else {
            status = .error
            onError?("Voice connection lost")
            return
        }
        let baseDelay = pow(2.0, Double(reconnectAttempts))
        let jitter = 0.5 + Double.random(in: 0..<0.5)
        let delay = baseDelay * jitter
        reconnectAttempts += 1

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.cleanupSession()
            self.connect()
        }
    }

    // MARK: - Cleanup

    private func cleanupSession() {
        receiveTask?.cancel()
        receiveTask = nil
        if let session = liveSession {
            Task { await session.close() }
        }
        liveSession = nil
    }
}
