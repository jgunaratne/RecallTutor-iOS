import Foundation

/// OpenAI Realtime voice session over WebSocket. The app uses this only with
/// a user-provided OpenAI key stored in the Keychain, matching its existing
/// direct Gemini key flow.
struct OpenAIRealtimeCallbacks {
    var onStatusChange: ((LiveSessionStatus) -> Void)?
    var onAudioChunk: ((String) -> Void)?
    var onTextChunk: ((String) -> Void)?
    var onTurnComplete: (() -> Void)?
    var onInterrupted: (() -> Void)?
    var onError: ((String) -> Void)?
}

@MainActor
final class OpenAIRealtimeSession {
    private static let model = "gpt-realtime-2.1"
    private static let inputSampleRate = 24_000

    private enum PendingResponse {
        case text(String)
        case audio
    }

    private(set) var status: LiveSessionStatus = .idle {
        didSet { if status != oldValue { callbacks.onStatusChange?(status) } }
    }

    private let callbacks: OpenAIRealtimeCallbacks
    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var sessionEpoch = 0
    /// Realtime permits just one active response per conversation. New card
    /// narration waits for the old response to finish cancelling.
    private var responseActive = false
    private var responseCancellationPending = false
    private var pendingResponse: PendingResponse?

    init(callbacks: OpenAIRealtimeCallbacks) {
        self.callbacks = callbacks
    }

    func connect(instructions: String, voice: String) {
        teardown()
        status = .connecting

        guard let apiKey = Keychain.loadKey(.openai) else {
            handleError("No OpenAI API key — add one in Settings.")
            return
        }

        var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?model=\(Self.model)")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        task.resume()

        let epoch = sessionEpoch
        receiveLoop = Task { [weak self] in
            await self?.runReceiveLoop(task: task, epoch: epoch)
        }

        send([
            "type": "session.update",
            "session": [
                "type": "realtime",
                "model": Self.model,
                "instructions": instructions,
                "output_modalities": ["audio"],
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": Self.inputSampleRate],
                        // Recall Tutor uses an explicit Ask button, so it owns
                        // turn boundaries instead of relying on background VAD.
                        "turn_detection": NSNull(),
                    ],
                    "output": [
                        // OpenAI requires the PCM output sample rate as well
                        // as its encoding. It must match the player format.
                        "format": ["type": "audio/pcm", "rate": Self.inputSampleRate],
                        "voice": voice,
                    ],
                ],
            ],
        ])
    }

    func sendAudio(_ base64Data: String) {
        guard status == .connected else { return }
        send(["type": "input_audio_buffer.append", "audio": base64Data])
    }

    /// Commit an explicit push-to-talk turn and ask the model to answer.
    func sendAudioStreamEnd() {
        guard status == .connected else { return }
        send(["type": "input_audio_buffer.commit"])
        if responseActive {
            pendingResponse = .audio
            cancelActiveResponse()
        } else {
            startAudioResponse()
        }
    }

    func sendContext(_ text: String) {
        sendTextItem(text)
    }

    func sendText(_ text: String) {
        guard status == .connected else { return }
        if responseActive {
            // A card flip can arrive while the previous card is still being
            // narrated. Keep only the newest request and start it after the
            // server confirms cancellation.
            pendingResponse = .text(text)
            cancelActiveResponse()
            return
        }
        startTextResponse(text)
    }

    // Note: no `output_audio_buffer.clear` anywhere below. Those events are
    // WebRTC-only — the server buffers audio on the media track there, so the
    // client asks it to drop what it queued. This session is a raw WebSocket:
    // audio arrives as `response.output_audio.delta` and the client owns the
    // buffer outright, so the server rejects the event with "Invalid value".
    // Stopping playback is `LiveAudioPlayer.flush()`, which the caller does.

    func cancelResponse() {
        guard status == .connected else { return }
        pendingResponse = nil
        cancelActiveResponse()
    }

    /// Open an explicit push-to-talk turn: interrupt the narration and drop
    /// any audio still sitting in the input buffer.
    ///
    /// The clear is the important half. Turn detection is disabled (see
    /// `connect`), so the server never resets the input buffer on its own —
    /// residue from an earlier turn stays there and gets prepended to the
    /// next `commit`, making the tutor answer a question the student never
    /// finished asking. Must run *before* capture starts.
    func beginQuestion() {
        guard status == .connected else { return }
        send(["type": "input_audio_buffer.clear"])
        cancelResponse()
    }

    func disconnect() {
        teardown()
        status = .idle
    }

    private func sendTextItem(_ text: String) {
        guard status == .connected else { return }
        send([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [["type": "input_text", "text": text]],
            ],
        ])
    }

    private func startTextResponse(_ text: String) {
        sendTextItem(text)
        startAudioResponse()
    }

    private func startAudioResponse() {
        // Set this before the server's response.created event so rapid card
        // changes cannot create overlapping response.create events.
        responseActive = true
        responseCancellationPending = false
        send([
            "type": "response.create",
            "response": ["output_modalities": ["audio"]],
        ])
    }

    private func cancelActiveResponse() {
        guard responseActive, !responseCancellationPending else { return }
        responseCancellationPending = true
        send(["type": "response.cancel"])
    }

    private func runReceiveLoop(task: URLSessionWebSocketTask, epoch: Int) async {
        do {
            while !Task.isCancelled {
                let message = try await task.receive()
                guard epoch == sessionEpoch else { return }
                let data: Data?
                switch message {
                case .data(let binaryData): data = binaryData
                case .string(let text): data = text.data(using: .utf8)
                @unknown default: data = nil
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                handleMessage(json)
            }
        } catch {
            guard epoch == sessionEpoch, status != .idle else { return }
            let reason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) }
            handleError(reason ?? "Voice connection lost")
        }
    }

    private func handleMessage(_ json: [String: Any]) {
        guard let type = json["type"] as? String else { return }
        switch type {
        case "session.updated":
            status = .connected
        case "response.created":
            responseActive = true
        case "response.output_audio.delta":
            if let audio = json["delta"] as? String { callbacks.onAudioChunk?(audio) }
        case "response.output_text.delta", "response.output_audio_transcript.delta":
            if let text = json["delta"] as? String { callbacks.onTextChunk?(text) }
        case "response.done":
            responseActive = false
            responseCancellationPending = false
            callbacks.onTurnComplete?()
            flushPendingResponse()
        case "input_audio_buffer.speech_started", "response.output_audio_buffer.cleared":
            callbacks.onInterrupted?()
        case "error":
            handleServerError(json["error"] as? [String: Any])
        default:
            break
        }
    }

    private func flushPendingResponse() {
        let pending = pendingResponse
        pendingResponse = nil
        guard let pending else { return }
        switch pending {
        case .text(let text): startTextResponse(text)
        case .audio: startAudioResponse()
        }
    }

    /// An `error` event never means the session is dead.
    ///
    /// OpenAI closes the socket itself for genuinely fatal problems (bad key,
    /// expired session) and `runReceiveLoop`'s catch reports that. Marking the
    /// session `.error` here as well meant one routine complaint — most often
    /// an empty-buffer commit from a quick Ask tap — tore down a perfectly
    /// live connection and told the student "Connection dropped — ask again."
    private func handleServerError(_ error: [String: Any]?) {
        let code = error?["code"] as? String

        // The optimistic `responseActive` flag can disagree with the server.
        // Resync, or `responseCancellationPending` latches on and blocks every
        // later cancel while a queued turn waits for a `response.done` that is
        // never coming.
        if code == "response_cancel_not_active" {
            responseActive = false
            responseCancellationPending = false
            flushPendingResponse()
            return
        }
        // Expected whenever a turn is committed with no speech in it.
        if code == "input_audio_buffer_commit_empty" { return }

        callbacks.onError?((error?["message"] as? String) ?? "OpenAI Realtime error")
    }

    private func handleError(_ message: String) {
        status = .error
        callbacks.onError?(message)
    }

    private func send(_ payload: [String: Any]) {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }

    private func teardown() {
        sessionEpoch += 1
        responseActive = false
        responseCancellationPending = false
        pendingResponse = nil
        receiveLoop?.cancel()
        receiveLoop = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}
