import AVFoundation
import Foundation

// Microphone capture and PCM playback for the Gemini Live voice tutor —
// AVAudioEngine counterparts of lib/audio-recorder.ts / lib/audio-player.ts.

/// Configure the shared audio session for simultaneous playback + capture.
enum LiveAudioSession {
    static func activate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? session.setActive(true)
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Recorder

/// Captures the mic, converts to 16 kHz 16-bit mono PCM, and emits
/// base64-encoded chunks.
final class LiveAudioRecorder {
    private let engine = AVAudioEngine()

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start(onChunk: @escaping (String) -> Void) throws {
        let input = engine.inputNode
        // Insert Apple's echo canceller. The .voiceChat session mode alone
        // does NOT enable AEC for a plain input tap — without this the
        // tutor's own speaker audio re-enters the mic and the server VAD
        // barge-ins against it, cutting the tutor off mid-sentence. Failure
        // is non-fatal: degrade to the raw mic rather than blocking it.
        try? input.setVoiceProcessingEnabled(true)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "LiveAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone unavailable"])
        }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "LiveAudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Audio converter unavailable"])
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            let ratio = 16_000 / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

            var consumed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, out.frameLength > 0, let channel = out.int16ChannelData else { return }
            let data = Data(bytes: channel[0], count: Int(out.frameLength) * 2)
            onChunk(data.base64EncodedString())
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

// MARK: - Player

/// Plays 24 kHz mono Int16 PCM chunks sequentially with barge-in flush.
final class LiveAudioPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!

    /// Serial generation counter — bumped on flush so stale buffer-completion
    /// callbacks from a stopped node can't corrupt the pending count.
    private var generation = 0
    private var pending = 0

    var onPlaybackStart: (() -> Void)?
    var onPlaybackEnd: (() -> Void)?

    var muted = false {
        didSet { node.volume = muted ? 0 : 1.5 } // 1.5 = web app's makeup gain
    }

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        node.volume = 1.5
    }

    func playChunk(_ base64: String) {
        guard let data = Data(base64Encoded: base64) else { return }
        let frames = data.count / 2
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return }
        buffer.frameLength = AVAudioFrameCount(frames)

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let samples = raw.bindMemory(to: Int16.self)
            let out = buffer.floatChannelData![0]
            for i in 0..<frames {
                out[i] = Float(samples[i]) / 32768
            }
        }

        if !engine.isRunning {
            try? engine.start()
        }

        if pending == 0 {
            onPlaybackStart?()
        }
        pending += 1
        let gen = generation
        node.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.generation == gen else { return }
                self.pending -= 1
                if self.pending <= 0 {
                    self.pending = 0
                    self.onPlaybackEnd?()
                }
            }
        }
        if !node.isPlaying {
            node.play()
        }
    }

    /// Barge-in: drop current + queued buffers but keep the engine alive so
    /// the model's next turn starts instantly.
    func flush() {
        generation += 1
        pending = 0
        node.stop()
        onPlaybackEnd?()
    }

    /// Full stop — tear the engine down.
    func stop() {
        generation += 1
        pending = 0
        node.stop()
        engine.stop()
        onPlaybackEnd?()
    }
}
