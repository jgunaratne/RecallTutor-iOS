import AVFoundation
import Foundation
import UIKit

/// Generates ~1-minute educational videos from lecture content.
///
/// Pipeline: Gemini script → 8× Veo segments (chained) → concatenate → TTS → mux.
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
    private static let veoModel = "veo-2.0-generate-001"
    private static let geminiModel = "gemini-2.5-flash"
    private static let segmentDuration = 8  // seconds (Veo max)
    private static let segmentCount = 8     // 8 × 8s = 64s ≈ 1 minute
    private static let pollInterval: TimeInterval = 15
    private static let maxPollsPerSegment = 40  // 10 min max per segment

    // MARK: - Main entry point

    /// Generate a ~1-minute educational video from lecture card content.
    ///
    /// - Parameters:
    ///   - cards: The lecture card text array (from CardSplitter).
    ///   - referenceImage: The card illustration to seed the first segment (optional).
    ///   - onStatus: Progress callback (fires on MainActor).
    /// - Returns: Local file URL of the final .mp4 with voiceover.
    static func generateFullVideo(
        cards: [String],
        referenceImage: UIImage? = nil,
        onStatus: @MainActor @Sendable @escaping (Status) -> Void
    ) async throws -> URL {
        guard let apiKey = Keychain.loadKey(.gemini) else {
            throw VideoError.noAPIKey
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lecture_video_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // ── Step 1: Generate narration script + scene prompts ──────────
        await onStatus(.preparingScript)
        let script = try await generateScript(cards: cards, apiKey: apiKey)

        // ── Step 2: Generate 8 Veo segments with frame chaining ────────
        var segmentURLs: [URL] = []
        var seedImage = referenceImage

        for i in 0..<min(script.scenes.count, Self.segmentCount) {
            try Task.checkCancellation()

            let scenePrompt = script.scenes[i].prompt
            let segmentURL = try await generateSingleSegment(
                prompt: scenePrompt,
                referenceImage: seedImage,
                segmentIndex: i,
                outputDir: tempDir,
                apiKey: apiKey,
                onStatus: onStatus
            )
            segmentURLs.append(segmentURL)

            // Extract last frame for chaining to next segment
            if i < Self.segmentCount - 1 {
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

        await onStatus(.complete)
        return finalURL
    }

    // MARK: - Step 1: Script generation

    /// Use Gemini to create a narration script + per-segment scene descriptions.
    private static func generateScript(cards: [String], apiKey: String) async throws -> VideoScript {
        let lectureContent = cards.joined(separator: "\n\n")
        let summary = String(lectureContent.prefix(3000))

        let prompt = """
        You are creating a 1-minute educational video. Given the lecture content below, create:

        1. A narration script (~150 words, paced for ~60 seconds of natural speech). \
        It should be engaging, clear, and educational — like a documentary narrator.

        2. Exactly \(segmentCount) scene descriptions for 8-second video segments. Each scene \
        should visually illustrate part of the narration with cinematic motion. \
        Describe camera movements, subjects, and visual style. No text/labels in the video.

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

        let url = URL(string: "\(baseURL)/models/\(geminiModel):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
            throw VideoError.scriptGenerationFailed
        }

        // Parse Gemini response → extract text → decode JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String,
              let scriptData = text.data(using: .utf8),
              let script = try? JSONDecoder().decode(VideoScript.self, from: scriptData)
        else {
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
        outputDir: URL,
        apiKey: String,
        onStatus: @MainActor @Sendable @escaping (Status) -> Void
    ) async throws -> URL {
        await onStatus(.generatingSegment(
            current: segmentIndex + 1, total: Self.segmentCount,
            poll: 0, maxPolls: Self.maxPollsPerSegment
        ))

        // Build request body (matches veo.service.ts Gemini API format)
        var body: [String: Any] = [
            "prompt": ["text": prompt],
            "generationConfig": [
                "durationSeconds": segmentDuration,
                "aspectRatio": "9:16",
                "personGeneration": "allow_all",
                "numberOfVideos": 1,
                "enhancePrompt": true,
            ] as [String: Any]
        ]

        if let image = referenceImage,
           let imageData = image.jpegData(compressionQuality: 0.85) {
            body["image"] = [
                "imageBytes": imageData.base64EncodedString(),
                "mimeType": "image/jpeg"
            ]
        }

        // Submit generation request
        let url = URL(string: "\(baseURL)/models/\(veoModel):generateVideo?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
                current: segmentIndex + 1, total: Self.segmentCount,
                poll: i + 1, maxPolls: Self.maxPollsPerSegment
            ))

            let pollURL = URL(string: "\(baseURL)/\(operationName)?key=\(apiKey)")!
            var pollRequest = URLRequest(url: pollURL)
            pollRequest.httpMethod = "GET"
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

            let resp = pollJson["response"] as? [String: Any] ?? [:]

            if let filterCount = resp["raiMediaFilteredCount"] as? Int, filterCount > 0 {
                let reason = (resp["raiMediaFilteredReasons"] as? [String])?.first
                    ?? "Content filtered by safety"
                throw VideoError.filtered(reason)
            }

            guard let videoBytes = extractVideoBytes(from: resp) else {
                throw VideoError.noVideoData(segment: segmentIndex)
            }

            guard let videoData = Data(base64Encoded: videoBytes) else {
                throw VideoError.noVideoData(segment: segmentIndex)
            }

            let segmentURL = outputDir.appendingPathComponent("segment_\(segmentIndex).mp4")
            try videoData.write(to: segmentURL)
            print("[VideoService] Segment \(segmentIndex + 1) saved (\(videoData.count) bytes)")
            return segmentURL
        }

        throw VideoError.timeout(segment: segmentIndex)
    }

    /// Walk the Veo response to find base64-encoded video data.
    /// Handles all known response shapes (from veo.service.ts lines 309–319).
    private static func extractVideoBytes(from resp: [String: Any]) -> String? {
        if let samples = resp["generatedSamples"] as? [[String: Any]],
           let video = samples.first?["video"] as? [String: Any] {
            if let b = video["videoBytes"] as? String { return b }
            if let b = video["bytesBase64Encoded"] as? String { return b }
        }
        if let videos = resp["videos"] as? [[String: Any]], let first = videos.first {
            if let b = first["videoBytes"] as? String { return b }
            if let b = first["bytesBase64Encoded"] as? String { return b }
        }
        if let preds = resp["predictions"] as? [[String: Any]],
           let b = preds.first?["bytesBase64Encoded"] as? String { return b }
        return nil
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
        let url = URL(string: "\(baseURL)/models/\(model):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        // Create AVAudioFormat for 24kHz PCM16LE
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: false) else {
            throw VideoError.exportFailed("Failed to create audio format")
        }
        
        let audioFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
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

        // Add audio track (trim to video length — equivalent to ffmpeg -shortest)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        if let sourceAudio = audioTracks.first,
           let compAudioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            let videoDuration = try await videoAsset.load(.duration)
            let audioDuration = try await audioAsset.load(.duration)
            let trimmedDuration = CMTimeMinimum(videoDuration, audioDuration)
            try compAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: trimmedDuration),
                of: sourceAudio,
                at: .zero
            )
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

        await exportSession.export()
        guard exportSession.status == .completed else {
            throw VideoError.exportFailed(exportSession.error?.localizedDescription ?? "Unknown")
        }

        print("[VideoService] Final video: \(finalURL.lastPathComponent)")
        return finalURL
    }
}
