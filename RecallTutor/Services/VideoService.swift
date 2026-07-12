import AVFoundation
import CryptoKit
import Foundation
import UIKit

/// Generates short educational videos (30 s / 1 min / 3 min) from lecture content.
///
/// Pipeline: Gemini script → N× 8 s Veo segments (chained) → concatenate → TTS → mux.
/// Port of VeoClip's veo.service.ts + mux.service.ts to native iOS.
enum VideoService {

    // MARK: - Types

    enum Status: Equatable {
        case preparingScript
        case generatingSegment(current: Int, total: Int, poll: Int, maxPolls: Int)
        case concatenating
        case generatingVoiceover
        case muxing
        case complete
        case error(String)

        var isDismissable: Bool {
            switch self {
            case .error, .complete: true
            default: false
            }
        }
    }

    enum VideoError: LocalizedError {
        case noAPIKey
        case apiError(Int, String)
        case timeout(segment: Int)
        case noVideoData(segment: Int)
        case filtered(String)
        case exportFailed(String)
        case scriptGenerationFailed
        case lastFrameExtractionFailed
        case ttsFailed

        var errorDescription: String? {
            switch self {
            case .noAPIKey: "No Gemini API key configured"
            case .apiError(let code, let msg): "API error (\(code)): \(msg)"
            case .timeout(let seg): "Segment \(seg + 1) generation timed out"
            case .noVideoData(let seg): "No video data for segment \(seg + 1)"
            case .filtered(let reason): "Content filtered: \(reason)"
            case .exportFailed(let msg): "Video export failed: \(msg)"
            case .scriptGenerationFailed: "Failed to generate narration script"
            case .lastFrameExtractionFailed: "Failed to extract frame for chaining"
            case .ttsFailed: "Voiceover generation failed"
            }
        }
    }

    /// User-selectable clip length. Veo segments are a fixed 8 s, so each
    /// option maps to a segment count; narration pacing scales with it.
    enum ClipLength: String, CaseIterable, Identifiable {
        case thirtySeconds
        case oneMinute
        case threeMinutes

        var id: String { rawValue }

        var label: String {
            switch self {
            case .thirtySeconds: "30 seconds"
            case .oneMinute: "1 minute"
            case .threeMinutes: "3 minutes"
            }
        }

        var segmentCount: Int {
            switch self {
            case .thirtySeconds: 4   // 32 s
            case .oneMinute: 8       // 64 s
            case .threeMinutes: 23   // 184 s
            }
        }

        var seconds: Int { segmentCount * VideoService.segmentDuration }

        /// Slightly under natural speech rate (~140 wpm) so the voiceover
        /// lands inside the video; mux time-scales any small overrun.
        var narrationWords: Int { seconds * 140 / 60 }
    }

    /// JSON response from Gemini for the narration + scene prompts.
    struct VideoScript: Codable {
        let narrationScript: String
        let scenes: [Scene]

        struct Scene: Codable {
            let prompt: String
        }
    }

    // MARK: - Constants

    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    private static let veoModel = "veo-3.1-fast-generate-preview"
    private static let geminiModel = GeminiModels.chat
    fileprivate static let segmentDuration = 8  // seconds (Veo max)
    private static let pollInterval: TimeInterval = 15
    private static let maxPollsPerSegment = 40  // 10 min max per segment

    // MARK: - Main entry point

    /// Generate an educational video of the chosen length from lecture cards.
    ///
    /// - Parameters:
    ///   - cards: The lecture card text array (from CardSplitter).
    ///   - length: Requested clip length (drives segment count + narration).
    ///   - referenceImage: The card illustration to seed the first segment (optional).
    ///   - onStatus: Progress callback (fires on MainActor).
    /// - Returns: Local file URL of the final .mp4 with voiceover.
    static func generateFullVideo(
        cards: [String],
        length: ClipLength,
        referenceImage: UIImage? = nil,
        onStatus: @MainActor @Sendable @escaping (Status) -> Void
    ) async throws -> URL {
        guard let apiKey = Keychain.loadKey(.gemini) else {
            throw VideoError.noAPIKey
        }

        // Keep running while minimized for as long as iOS allows. When the
        // grant expires the app suspends (Veo keeps rendering server-side)
        // and polling resumes where it left off on foreground.
        let bgTask = await MainActor.run { BackgroundTaskGuard(name: "LectureVideoGeneration") }
        defer { bgTask.end() }

        // Same lecture + length → same video; serve the cached render instantly.
        let cachedURL = cacheURL(for: cards, length: length)
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            print("[VideoService] Cache hit: \(cachedURL.lastPathComponent)")
            await onStatus(.complete)
            return cachedURL
        }

        // Sweep work dirs orphaned by runs the process didn't survive
        // (app killed mid-generation) — in-process failures clean up after
        // themselves, but nothing else does.
        let tmpRoot = FileManager.default.temporaryDirectory
        if let leftovers = try? FileManager.default.contentsOfDirectory(at: tmpRoot, includingPropertiesForKeys: nil) {
            for item in leftovers where item.lastPathComponent.hasPrefix("lecture_video_") {
                try? FileManager.default.removeItem(at: item)
            }
        }

        let tempDir = tmpRoot
            .appendingPathComponent("lecture_video_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        do {
            // ── Step 1: Generate narration script + scene prompts ──────────
            await onStatus(.preparingScript)
            let script = try await generateScript(cards: cards, length: length, apiKey: apiKey)

            // ── Step 2: Generate Veo segments with frame chaining ──────────
            var segmentURLs: [URL] = []
            var seedImage = referenceImage

            for i in 0..<min(script.scenes.count, length.segmentCount) {
                try Task.checkCancellation()

                let scenePrompt = script.scenes[i].prompt
                let segmentURL: URL
                do {
                    segmentURL = try await generateSingleSegment(
                        prompt: scenePrompt,
                        referenceImage: seedImage,
                        segmentIndex: i,
                        totalSegments: length.segmentCount,
                        outputDir: tempDir,
                        apiKey: apiKey,
                        onStatus: onStatus
                    )
                } catch VideoError.filtered(let reason) {
                    // Don't let one filtered scene sink the whole run —
                    // retry once with a deliberately safe abstract prompt.
                    print("[VideoService] Segment \(i + 1) filtered (\(reason)); retrying with sanitized prompt")
                    segmentURL = try await generateSingleSegment(
                        prompt: """
                        A slow cinematic camera drift through an abstract, softly lit \
                        landscape of light, color, and gentle shapes, evoking a calm \
                        documentary mood. Ambient sound only. No people, no text, no dialogue.
                        """,
                        referenceImage: seedImage,
                        segmentIndex: i,
                        totalSegments: length.segmentCount,
                        outputDir: tempDir,
                        apiKey: apiKey,
                        onStatus: onStatus
                    )
                }
                segmentURLs.append(segmentURL)

                // Extract last frame for chaining to next segment
                if i < length.segmentCount - 1 {
                    seedImage = try? await extractLastFrame(from: segmentURL)
                    if seedImage == nil {
                        print("[VideoService] Warning: couldn't extract last frame for segment \(i), next segment won't be chained")
                    }
                }
            }

            try Task.checkCancellation()

            // ── Step 3: Concatenate all segments ───────────────────────────
            await onStatus(.concatenating)
            let joinedVideoURL = try await concatenateSegments(segmentURLs, outputDir: tempDir)

            // ── Step 4: Generate TTS voiceover ─────────────────────────────
            await onStatus(.generatingVoiceover)
            let audioURL = try await generateVoiceover(
                script: script.narrationScript,
                apiKey: apiKey,
                outputDir: tempDir
            )

            // ── Step 5: Mux video + audio ──────────────────────────────────
            await onStatus(.muxing)
            let finalURL = try await muxVideoAndAudio(
                videoURL: joinedVideoURL,
                audioURL: audioURL,
                outputDir: tempDir
            )

            // Promote the finished video into the cache, then drop the
            // segments and intermediates.
            try? FileManager.default.removeItem(at: cachedURL)
            try FileManager.default.moveItem(at: finalURL, to: cachedURL)
            try? FileManager.default.removeItem(at: tempDir)

            await onStatus(.complete)
            return cachedURL
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            throw error
        }
    }

    // MARK: - Background execution

    /// Holds a UIKit background-task grant for the duration of a generation
    /// so minimizing the app doesn't immediately freeze the pipeline. If the
    /// grant expires we end it cleanly (required, or iOS kills the app) and
    /// let normal suspension take over — polling resumes on foreground.
    private final class BackgroundTaskGuard: @unchecked Sendable {
        private var id: UIBackgroundTaskIdentifier = .invalid
        private let lock = NSLock()

        @MainActor
        init(name: String) {
            id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
                self?.end()
            }
        }

        func end() {
            lock.lock()
            let current = id
            id = .invalid
            lock.unlock()
            guard current != .invalid else { return }
            Task { @MainActor in
                UIApplication.shared.endBackgroundTask(current)
            }
        }
    }

    // MARK: - Cache

    /// Whether a finished video for this lecture + length is already cached.
    static func hasCachedVideo(for cards: [String], length: ClipLength) -> Bool {
        FileManager.default.fileExists(atPath: cacheURL(for: cards, length: length).path)
    }

    /// Stable per-lecture cache location, keyed by a hash of the card text
    /// and the clip length (a 30 s and a 3 min render coexist).
    /// Lives in Caches so the system can reclaim it under storage pressure.
    private static func cacheURL(for cards: [String], length: ClipLength) -> URL {
        let digest = SHA256.hash(data: Data(cards.joined(separator: "\n").utf8))
        let hash = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LectureVideos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("lecture_\(hash)_\(length.seconds)s.mp4")
    }

    // MARK: - Step 1: Script generation

    /// Use Gemini to create a narration script + per-segment scene descriptions.
    private static func generateScript(cards: [String], length: ClipLength, apiKey: String) async throws -> VideoScript {
        let lectureContent = cards.joined(separator: "\n\n")
        let summary = String(lectureContent.prefix(3000))

        let prompt = """
        You are creating a \(length.seconds)-second educational video. Given the lecture content below, create:

        1. A narration script of AT MOST \(length.narrationWords) words, paced to finish within \
        \(length.seconds) seconds of natural speech — it must not run over. \
        It should be engaging, clear, and educational — like a documentary narrator.

        2. Exactly \(length.segmentCount) scene descriptions for 8-second video segments. Each scene \
        should visually illustrate part of the narration with cinematic motion. \
        Describe camera movements, subjects, and visual style. The scenes must be purely \
        visual with ambient sound only: no dialogue, speech, singing, or quoted text, and \
        no on-screen text or labels. Keep imagery symbolic and family-friendly — avoid \
        violence, weapons, suffering, and identifiable real or historical people (use \
        anonymous, stylized figures instead) so the scenes pass video safety filters.

        Lecture content:
        \(summary)

        Return ONLY valid JSON (no markdown fences) with this structure:
        {
          "narrationScript": "The full narration text...",
          "scenes": [
            {"prompt": "Scene 1 description..."},
            {"prompt": "Scene 2 description..."}
          ]
        }
        """

        let url = URL(string: "\(baseURL)/models/\(geminiModel):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.7,
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw VideoError.apiError(
                (response as? HTTPURLResponse)?.statusCode ?? 0,
                String(body.prefix(300))
            )
        }

        // Parse Gemini response → extract text → decode JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else {
            print("[VideoService] Unexpected script response: \(String(data: data, encoding: .utf8)?.prefix(500) ?? "nil")")
            throw VideoError.scriptGenerationFailed
        }

        // Join every text part — thinking models may split output — and
        // strip code fences Gemini sometimes adds despite instructions.
        var text = parts.compactMap { $0["text"] as? String }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let scriptData = text.data(using: .utf8),
              let script = try? JSONDecoder().decode(VideoScript.self, from: scriptData)
        else {
            print("[VideoService] Script JSON didn't decode: \(text.prefix(500))")
            throw VideoError.scriptGenerationFailed
        }

        print("[VideoService] Script generated: \(script.narrationScript.prefix(100))…")
        print("[VideoService] Scene count: \(script.scenes.count)")
        return script
    }

    // MARK: - Step 2: Single Veo segment generation

    /// Generate one 8-second video segment via the Gemini Veo API.
    /// Ported from veo.service.ts:generateVideoGemini (lines 218–348).
    private static func generateSingleSegment(
        prompt: String,
        referenceImage: UIImage?,
        segmentIndex: Int,
        totalSegments: Int,
        outputDir: URL,
        apiKey: String,
        onStatus: @MainActor @Sendable @escaping (Status) -> Void
    ) async throws -> URL {
        await onStatus(.generatingSegment(
            current: segmentIndex + 1, total: totalSegments,
            poll: 0, maxPolls: Self.maxPollsPerSegment
        ))

        // Build request body — Gemini Veo uses instances/parameters, and the
        // seed image rides along as inlineData on the instance.
        var instance: [String: Any] = ["prompt": prompt]

        if let image = referenceImage,
           let imageData = image.jpegData(compressionQuality: 0.85) {
            instance["image"] = [
                "bytesBase64Encoded": imageData.base64EncodedString(),
                "mimeType": "image/jpeg",
            ]
        }

        let body: [String: Any] = [
            "instances": [instance],
            "parameters": [
                "durationSeconds": segmentDuration,
                "aspectRatio": "9:16",
                "personGeneration": "allow_all",
            ] as [String: Any]
        ]

        // Submit generation request
        let url = URL(string: "\(baseURL)/models/\(veoModel):predictLongRunning")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? ""
            throw VideoError.apiError(
                (response as? HTTPURLResponse)?.statusCode ?? 0,
                String(errorText.prefix(300))
            )
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let operationName = json["name"] as? String else {
            throw VideoError.apiError(0, "No operation name in Veo response")
        }

        print("[VideoService] Segment \(segmentIndex + 1) LRO: \(operationName)")

        // Poll for completion (GET on operation URL — Gemini API pattern)
        for i in 0..<Self.maxPollsPerSegment {
            try await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
            try Task.checkCancellation()

            await onStatus(.generatingSegment(
                current: segmentIndex + 1, total: totalSegments,
                poll: i + 1, maxPolls: Self.maxPollsPerSegment
            ))

            let pollURL = URL(string: "\(baseURL)/\(operationName)")!
            var pollRequest = URLRequest(url: pollURL)
            pollRequest.httpMethod = "GET"
            pollRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            pollRequest.timeoutInterval = 30

            guard let (pollData, pollResp) = try? await URLSession.shared.data(for: pollRequest),
                  let pollHttp = pollResp as? HTTPURLResponse,
                  pollHttp.statusCode == 200,
                  let pollJson = try? JSONSerialization.jsonObject(with: pollData) as? [String: Any]
            else {
                print("[VideoService] Segment \(segmentIndex + 1) poll \(i + 1) failed, retrying…")
                continue
            }

            guard let done = pollJson["done"] as? Bool, done else {
                print("[VideoService] Segment \(segmentIndex + 1) poll \(i + 1)/\(Self.maxPollsPerSegment) — running…")
                continue
            }

            if let error = pollJson["error"] as? [String: Any] {
                let msg = (error["message"] as? String) ?? "Unknown error"
                throw VideoError.apiError(0, msg)
            }

            // Veo nests its payload one level down, under generateVideoResponse.
            let outer = pollJson["response"] as? [String: Any] ?? [:]
            let resp = outer["generateVideoResponse"] as? [String: Any] ?? outer

            if let filterCount = resp["raiMediaFilteredCount"] as? Int, filterCount > 0 {
                let reason = (resp["raiMediaFilteredReasons"] as? [String])?.first
                    ?? "Content filtered by safety"
                throw VideoError.filtered(reason)
            }

            let segmentURL = outputDir.appendingPathComponent("segment_\(segmentIndex).mp4")

            guard let sample = (resp["generatedSamples"] as? [[String: Any]])?.first,
                  let video = sample["video"] as? [String: Any] else {
                throw VideoError.noVideoData(segment: segmentIndex)
            }

            // The API hands back a URI to fetch, not the bytes themselves.
            if let uri = video["uri"] as? String {
                let videoData = try await downloadVideo(uri: uri, apiKey: apiKey, segmentIndex: segmentIndex)
                try videoData.write(to: segmentURL)
                print("[VideoService] Segment \(segmentIndex + 1) saved (\(videoData.count) bytes)")
                return segmentURL
            }

            // Some responses inline the bytes instead; accept either.
            guard let base64 = (video["videoBytes"] as? String) ?? (video["bytesBase64Encoded"] as? String),
                  let videoData = Data(base64Encoded: base64) else {
                throw VideoError.noVideoData(segment: segmentIndex)
            }

            try videoData.write(to: segmentURL)
            print("[VideoService] Segment \(segmentIndex + 1) saved (\(videoData.count) bytes)")
            return segmentURL
        }

        throw VideoError.timeout(segment: segmentIndex)
    }

    /// Fetch the rendered segment from the file URI Veo returns.
    /// The URI is not pre-signed; it needs the API key like any other call.
    private static func downloadVideo(uri: String, apiKey: String, segmentIndex: Int) async throws -> Data {
        guard let url = URL(string: uri) else {
            throw VideoError.noVideoData(segment: segmentIndex)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 120

        // Retry: a download in flight when the app suspends fails on resume.
        var lastError: Error = VideoError.noVideoData(segment: segmentIndex)
        for attempt in 1...3 {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw VideoError.apiError(
                        (response as? HTTPURLResponse)?.statusCode ?? 0,
                        "Failed to download segment \(segmentIndex + 1)"
                    )
                }
                guard !data.isEmpty else {
                    throw VideoError.noVideoData(segment: segmentIndex)
                }
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                print("[VideoService] Segment \(segmentIndex + 1) download attempt \(attempt) failed: \(error.localizedDescription)")
                if attempt < 3 {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
        throw lastError
    }

    // MARK: - Step 2b: Extract last frame for chaining

    /// Extract the last frame from a video segment for chaining.
    /// Equivalent to VeoClip's mux.service.ts extractLastFrame (ffmpeg -sseof).
    private static func extractLastFrame(from videoURL: URL) async throws -> UIImage {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)

        // Request the very last frame
        let lastTime = CMTimeSubtract(duration, CMTime(seconds: 0.05, preferredTimescale: 600))
        let (cgImage, _) = try await generator.image(at: lastTime)
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Step 3: Concatenate segments

    /// Stitch all segment videos into one continuous video.
    /// iOS equivalent of VeoClip's mux.service.ts concat (ffmpeg concat demuxer).
    private static func concatenateSegments(_ segmentURLs: [URL], outputDir: URL) async throws -> URL {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoError.exportFailed("Failed to create video track")
        }

        var currentTime = CMTime.zero

        for segmentURL in segmentURLs {
            let asset = AVURLAsset(url: segmentURL)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let sourceTrack = tracks.first else { continue }

            let timeRange = CMTimeRange(start: .zero, duration: duration)
            try videoTrack.insertTimeRange(timeRange, of: sourceTrack, at: currentTime)
            currentTime = CMTimeAdd(currentTime, duration)
        }

        // Export concatenated video
        let outputURL = outputDir.appendingPathComponent("joined_video.mp4")
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoError.exportFailed("Failed to create export session")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        await exportSession.export()
        guard exportSession.status == .completed else {
            throw VideoError.exportFailed(exportSession.error?.localizedDescription ?? "Unknown")
        }

        print("[VideoService] Concatenated \(segmentURLs.count) segments → \(outputURL.lastPathComponent)")
        return outputURL
    }

    // MARK: - Step 4: TTS voiceover

    /// Render narration text to an audio file using Gemini TTS API.
    /// Uses gemini-3.1-flash-tts-preview to generate 24kHz PCM16LE audio.
    private static func generateVoiceover(script: String, apiKey: String, outputDir: URL) async throws -> URL {
        let model = "gemini-3.1-flash-tts-preview"
        let url = URL(string: "\(baseURL)/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": script]]]],
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": [
                    "voiceConfig": [
                        "prebuiltVoiceConfig": ["voiceName": "Kore"]
                    ]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw VideoError.ttsFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let inlineData = parts.first(where: { $0["inlineData"] != nil })?["inlineData"] as? [String: Any],
              let base64 = inlineData["data"] as? String,
              let pcmData = Data(base64Encoded: base64)
        else {
            throw VideoError.ttsFailed
        }

        let audioURL = outputDir.appendingPathComponent("voiceover.wav")
        // 24kHz PCM16 mono, interleaved (WAV is interleaved; mono is identical
        // bytes either way). The file's processing format must match the
        // buffer we write or CoreAudio's converter assert-crashes.
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true) else {
            throw VideoError.exportFailed("Failed to create audio format")
        }

        let audioFile = try AVAudioFile(
            forWriting: audioURL,
            settings: format.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        let frameCapacity = AVAudioFrameCount(pcmData.count / 2)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            throw VideoError.exportFailed("Failed to create PCM buffer")
        }
        
        pcmBuffer.frameLength = frameCapacity
        
        pcmData.withUnsafeBytes { rawBufferPointer in
            if let ptr = rawBufferPointer.bindMemory(to: Int16.self).baseAddress,
               let channelData = pcmBuffer.int16ChannelData?[0] {
                channelData.update(from: ptr, count: Int(frameCapacity))
            }
        }
        
        try audioFile.write(from: pcmBuffer)
        return audioURL
    }

    // MARK: - Step 5: Mux video + audio

    /// Combine the concatenated video with the TTS voiceover audio.
    /// iOS equivalent of VeoClip's mux.service.ts muxVideoAndAudio (ffmpeg).
    private static func muxVideoAndAudio(videoURL: URL, audioURL: URL, outputDir: URL) async throws -> URL {
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        let composition = AVMutableComposition()

        // Add video track
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        if let sourceVideo = videoTracks.first,
           let compVideoTrack = composition.addMutableTrack(
               withMediaType: .video,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            let videoDuration = try await videoAsset.load(.duration)
            try compVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: videoDuration),
                of: sourceVideo,
                at: .zero
            )
        }

        // Add the full narration; if it runs past the video, time-scale it
        // to fit (pitch-preserved via the export's time-pitch algorithm)
        // instead of chopping it off mid-sentence.
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        if let sourceAudio = audioTracks.first,
           let compAudioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            let videoDuration = try await videoAsset.load(.duration)
            let audioDuration = try await audioAsset.load(.duration)
            try compAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: audioDuration),
                of: sourceAudio,
                at: .zero
            )
            if audioDuration > videoDuration {
                compAudioTrack.scaleTimeRange(
                    CMTimeRange(start: .zero, duration: audioDuration),
                    toDuration: videoDuration
                )
                let speedup = audioDuration.seconds / videoDuration.seconds
                print("[VideoService] Narration overran video by \(String(format: "%.1f", (speedup - 1) * 100))%; time-scaled to fit")
            }
        }

        // Export final muxed video
        let finalURL = outputDir.appendingPathComponent("lecture_video_final.mp4")
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoError.exportFailed("Failed to create mux export session")
        }

        exportSession.outputURL = finalURL
        exportSession.outputFileType = .mp4
        // Keeps the narrator's pitch natural when the audio was time-scaled.
        exportSession.audioTimePitchAlgorithm = .spectral

        await exportSession.export()
        guard exportSession.status == .completed else {
            throw VideoError.exportFailed(exportSession.error?.localizedDescription ?? "Unknown")
        }

        print("[VideoService] Final video: \(finalURL.lastPathComponent)")
        return finalURL
    }
}
