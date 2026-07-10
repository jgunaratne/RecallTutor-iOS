import Foundation

// Gemini Live session — port of lib/gemini-live-session.ts, speaking the
// BidiGenerateContent WebSocket protocol directly (no SDK on iOS).
//
// Handles: setup handshake, realtime audio in (16 kHz PCM16 base64),
// audio/text out, keepalive silent frames, GoAway reconnection with
// session resumption, and barge-in interruption signals.

enum LiveSessionStatus {
    case idle, connecting, connected, error
}

struct GeminiLiveCallbacks {
    var onStatusChange: ((LiveSessionStatus) -> Void)?
    var onAudioChunk: ((String) -> Void)?
    var onTextChunk: ((String) -> Void)?
    var onTurnComplete: (() -> Void)?
    /** Barge-in: the server cut the model off because the user spoke. */
    var onInterrupted: (() -> Void)?
    var onError: ((String) -> Void)?
}

@MainActor
final class GeminiLiveSession {
    private static let model = "models/gemini-3.1-flash-live-preview"
    private static let keepaliveInterval: TimeInterval = 15
    private static let maxGoAwayReconnects = 3

    /// 10 ms of silence at 16 kHz, 16-bit mono PCM = 320 zero bytes.
    private static let silentFrameBase64 = Data(count: 320).base64EncodedString()

    private(set) var status: LiveSessionStatus = .idle {
        didSet { if status != oldValue { callbacks.onStatusChange?(status) } }
    }

    private let callbacks: GeminiLiveCallbacks
    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var keepaliveTask: Task<Void, Never>?

    // GoAway reconnection bookkeeping — the server periodically recycles
    // long-lived connections; the resumption handle restores the context.
    private var systemInstruction = ""
    private var voice = "Puck"
    private var goAwayReceived = false
    private var reconnectAttempts = 0
    private var sessionEpoch = 0
    private var resumptionHandle: String?
    private var lastAudioSentAt = Date.distantPast

    init(callbacks: GeminiLiveCallbacks) {
        self.callbacks = callbacks
    }

    // MARK: - Public API

    func connect(systemInstruction: String, voice: String) {
        self.systemInstruction = systemInstruction
        self.voice = voice
        resumptionHandle = nil
        reconnectAttempts = 0
        doConnect()
    }

    /// Send raw microphone audio (base64-encoded PCM16 16 kHz). Safe to call
    /// from any thread via nonisolated send below.
    func sendAudio(_ base64Data: String) {
        lastAudioSentAt = Date()
        send(["realtimeInput": ["audio": ["data": base64Data, "mimeType": "audio/pcm;rate=16000"]]])
    }

    /// Tell the server the mic was turned off, so voice activity detection
    /// commits the user's turn instead of waiting for trailing silence.
    func sendAudioStreamEnd() {
        send(["realtimeInput": ["audioStreamEnd": true]])
    }

    /// Seed context without triggering a model response. Only honoured
    /// before the first sendText — after that, fold context into sendText.
    func sendContext(_ text: String) {
        send([
            "clientContent": [
                "turns": [["role": "user", "parts": [["text": text]]]],
                "turnComplete": false,
            ]
        ])
    }

    /// Send text that triggers a model response.
    func sendText(_ text: String) {
        send([
            "clientContent": [
                "turns": [["role": "user", "parts": [["text": text]]]],
                "turnComplete": true,
            ]
        ])
    }

    func disconnect() {
        teardown()
        goAwayReceived = false
        reconnectAttempts = 0
        resumptionHandle = nil
        status = .idle
    }

    // MARK: - Connection

    private func doConnect() {
        teardown()
        goAwayReceived = false
        status = .connecting

        guard let apiKey = Keychain.loadKey(.gemini) else {
            handleError("No Gemini API key — add one in Settings.")
            return
        }

        let epoch = sessionEpoch
        var request = URLRequest(url: URL(string:
            "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
        )!)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 15

        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        task.resume()

        // Setup message — mirrors the web app's session config.
        var setup: [String: Any] = [
            "model": Self.model,
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": [
                    "voiceConfig": ["prebuiltVoiceConfig": ["voiceName": voice]]
                ],
            ],
            "systemInstruction": ["parts": [["text": systemInstruction]]],
            "realtimeInputConfig": [
                "turnCoverage": "TURN_INCLUDES_ONLY_ACTIVITY",
                "automaticActivityDetection": [
                    "startOfSpeechSensitivity": "START_SENSITIVITY_HIGH",
                    "endOfSpeechSensitivity": "END_SENSITIVITY_LOW",
                    "silenceDurationMs": 1000,
                    "prefixPaddingMs": 100,
                ],
            ],
            // Resumption restores conversation state after a GoAway reconnect;
            // sliding-window compression lifts the context-size cap so one
            // session spans lecture + quiz.
            "contextWindowCompression": ["slidingWindow": [:] as [String: Any]],
        ]
        if let handle = resumptionHandle {
            setup["sessionResumption"] = ["handle": handle]
        } else {
            setup["sessionResumption"] = [:] as [String: Any]
        }
        send(["setup": setup])

        receiveLoop = Task { [weak self] in
            await self?.runReceiveLoop(task: task, epoch: epoch)
        }
    }

    private func runReceiveLoop(task: URLSessionWebSocketTask, epoch: Int) async {
        do {
            while !Task.isCancelled {
                let message = try await task.receive()
                guard epoch == sessionEpoch else { return }

                let data: Data?
                switch message {
                case .data(let d): data = d
                case .string(let s): data = s.data(using: .utf8)
                @unknown default: data = nil
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                handleMessage(json)
            }
        } catch {
            guard epoch == sessionEpoch else { return }
            stopKeepalive()

            // Attempt transparent reconnection on GoAway (or unexpected drop
            // mid-session), resuming context via the resumption handle.
            if (goAwayReceived || status == .connected), reconnectAttempts < Self.maxGoAwayReconnects {
                reconnectAttempts += 1
                doConnect()
                return
            }
            if status == .connected || status == .connecting {
                handleError("Voice connection lost")
            }
        }
    }

    private func handleMessage(_ json: [String: Any]) {
        // Setup handshake complete — we're live.
        if json["setupComplete"] != nil {
            reconnectAttempts = 0
            status = .connected
            startKeepalive()
            return
        }

        // GoAway — the server wants us to reconnect; the socket close follows.
        if json["goAway"] != nil {
            goAwayReceived = true
            return
        }

        // Remember the latest resumable handle for GoAway reconnects.
        if let update = json["sessionResumptionUpdate"] as? [String: Any] {
            if update["resumable"] as? Bool == true, let handle = update["newHandle"] as? String {
                resumptionHandle = handle
            }
            return
        }

        guard let content = json["serverContent"] as? [String: Any] else { return }

        if let modelTurn = content["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            for part in parts {
                if let inline = part["inlineData"] as? [String: Any], let audio = inline["data"] as? String {
                    callbacks.onAudioChunk?(audio)
                }
                if let text = part["text"] as? String {
                    callbacks.onTextChunk?(text)
                }
            }
        }

        if content["turnComplete"] as? Bool == true {
            callbacks.onTurnComplete?()
        }

        // Barge-in: the user spoke over the model — playback should be flushed.
        if content["interrupted"] as? Bool == true {
            callbacks.onInterrupted?()
        }
    }

    private func handleError(_ message: String) {
        status = .error
        callbacks.onError?(message)
    }

    private func send(_ payload: [String: Any]) {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in
            // Errors surface through the receive loop.
        }
    }

    private func teardown() {
        stopKeepalive()
        sessionEpoch += 1
        receiveLoop?.cancel()
        receiveLoop = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    // MARK: - Keepalive

    private func startKeepalive() {
        stopKeepalive()
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.keepaliveInterval))
                guard let self, !Task.isCancelled else { return }
                // Skip while real mic audio is flowing — injecting silence
                // mid-speech corrupts the stream the VAD is analyzing.
                if Date().timeIntervalSince(self.lastAudioSentAt) < Self.keepaliveInterval { continue }
                self.send(["realtimeInput": ["audio": ["data": Self.silentFrameBase64, "mimeType": "audio/pcm;rate=16000"]]])
            }
        }
    }

    private func stopKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = nil
    }
}
