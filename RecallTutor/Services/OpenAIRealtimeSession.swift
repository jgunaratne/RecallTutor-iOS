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

    private(set) var status: LiveSessionStatus = .idle {
        didSet { if status != oldValue { callbacks.onStatusChange?(status) } }
    }

    private let callbacks: OpenAIRealtimeCallbacks
    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var sessionEpoch = 0

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
        send(["type": "response.create"])
    }

    func sendContext(_ text: String) {
        sendTextItem(text)
    }

    func sendText(_ text: String) {
        guard status == .connected else { return }
        sendTextItem(text)
        send(["type": "response.create"])
    }

    func cancelResponse() {
        guard status == .connected else { return }
        send(["type": "response.cancel"])
        send(["type": "output_audio_buffer.clear"])
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
        case "response.output_audio.delta":
            if let audio = json["delta"] as? String { callbacks.onAudioChunk?(audio) }
        case "response.output_text.delta", "response.output_audio_transcript.delta":
            if let text = json["delta"] as? String { callbacks.onTextChunk?(text) }
        case "response.done":
            callbacks.onTurnComplete?()
        case "input_audio_buffer.speech_started", "response.output_audio_buffer.cleared":
            callbacks.onInterrupted?()
        case "error":
            let message = (json["error"] as? [String: Any])?["message"] as? String
            handleError(message ?? "OpenAI Realtime error")
        default:
            break
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
        task.send(.string(text)) { _ in }
    }

    private func teardown() {
        sessionEpoch += 1
        receiveLoop?.cancel()
        receiveLoop = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}
