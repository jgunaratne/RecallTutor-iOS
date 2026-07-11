import Foundation
import Observation
import UIKit

/// Generates illustrative images for lecture cards using Gemini's
/// Nano Banana Flash Lite image model (gemini-3.1-flash-lite-image)
/// via the Interactions API. Manages an in-memory cache so images
/// survive card-swipe navigation within a single lecture session.
///
/// Usage: create one instance per lecture, call `generateImages(for:)`
/// once streaming finishes, and query `images[cardIndex]` to render.
@Observable
@MainActor
final class CardImageGenerator {

    /// Generated images keyed by card index.
    private(set) var images: [Int: UIImage] = [:]

    /// Card indices currently being generated.
    private(set) var generating: Set<Int> = []

    /// Card indices that failed generation (won't auto-retry).
    private var failed: Set<Int> = []

    /// In-flight tasks so we can cancel on reset.
    private var tasks: [Int: Task<Void, Never>] = [:]

    // MARK: - Public

    /// Kick off image generation for eligible cards. Safe to call
    /// repeatedly — already-cached or in-flight indices are skipped.
    func generateImages(for cards: [String]) {
        guard Keychain.loadKey(.gemini) != nil else { return }
        let eligible = Self.imageIndices(for: cards)
        for index in eligible {
            guard images[index] == nil,
                  !generating.contains(index),
                  !failed.contains(index) else { continue }

            generating.insert(index)
            let content = cards[index]
            tasks[index] = Task {
                defer {
                    generating.remove(index)
                    tasks.removeValue(forKey: index)
                }
                do {
                    let image = try await Self.callImageGen(cardContent: content)
                    if !Task.isCancelled {
                        images[index] = image
                    }
                } catch {
                    if !Task.isCancelled {
                        failed.insert(index)
                    }
                }
            }
        }
    }

    /// Cancel all in-flight work and clear the cache.
    func reset() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        images.removeAll()
        generating.removeAll()
        failed.removeAll()
    }

    /// Pick which cards get illustrations: the 3 most text-heavy cards
    /// (minimum 150 chars). These are the cards that benefit most from
    /// a visual break to complement the dense content.
    static func imageIndices(for cards: [String]) -> Set<Int> {
        guard cards.count > 1 else { return [] }
        // Rank cards by character count, pick the top 3 that exceed
        // the minimum threshold.
        let ranked = cards.enumerated()
            .filter { $0.element.count > 150 }
            .sorted { $0.element.count > $1.element.count }
            .prefix(3)
        return Set(ranked.map(\.offset))
    }

    // MARK: - Gemini Interactions API (Nano Banana)

    /// Nano Banana 2 — the versatile workhorse image model.
    /// Note: the lite variant (gemini-3.1-flash-lite-image) is not currently
    /// listed in the Interactions API supported models, so we use the
    /// standard flash-image model instead.
    private static let imageModel = "gemini-3.1-flash-image"
    private static let base = "https://generativelanguage.googleapis.com/v1beta"

    private static func callImageGen(cardContent: String) async throws -> UIImage {
        guard let apiKey = Keychain.loadKey(.gemini) else {
            throw ImageGenError.noKey
        }

        // Build a focused illustration prompt from the card text.
        let prompt = """
        Create a simple, clean educational illustration that visually \
        represents the key concept described below. Use a flat design \
        style with soft, harmonious colors on a light background. Do not \
        include any text, labels, or words in the image. The illustration \
        should be conceptual and elegant:

        \(String(cardContent.prefix(600)))
        """

        // Interactions API format per
        // https://ai.google.dev/gemini-api/docs/image-generation
        let body: [String: Any] = [
            "model": imageModel,
            "input": [
                ["type": "text", "text": prompt],
            ],
        ]

        var request = URLRequest(
            url: URL(string: "\(base)/interactions")!
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ImageGenError.badResponse
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "(non-utf8)"
            print("[CardImageGen] HTTP \(http.statusCode): \(body.prefix(500))")
            throw ImageGenError.badResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[CardImageGen] Failed to parse JSON response")
            throw ImageGenError.badResponse
        }

        if let image = Self.extractImage(from: json) {
            return image
        }

        // Log the top-level keys so we can diagnose the response shape
        print("[CardImageGen] No image found. Response keys: \(json.keys.sorted())")
        throw ImageGenError.noImage
    }

    /// Walk the Interactions REST response to find base64-encoded image data.
    ///
    /// Interactions API REST response shape:
    /// ```
    /// {
    ///   "steps": [{
    ///     "type": "model_output",
    ///     "content": [
    ///       {"type": "image", "data": "BASE64...", "mime_type": "image/png"}
    ///     ]
    ///   }]
    /// }
    /// ```
    /// The `output_image` convenience property is SDK-only (not in REST).
    private static func extractImage(from json: [String: Any]) -> UIImage? {
        // Shape 1 (REST): steps[].content[] with {type: "image", data: "..."}
        if let steps = json["steps"] as? [[String: Any]] {
            for step in steps {
                // The Interactions API uses "content" (not "parts")
                if let content = step["content"] as? [[String: Any]] {
                    for block in content {
                        if let type = block["type"] as? String, type == "image",
                           let b64 = block["data"] as? String,
                           let imageData = Data(base64Encoded: b64),
                           let image = UIImage(data: imageData) {
                            return image
                        }
                    }
                }
                // Fallback: also check "parts" (in case the API shape varies)
                if let parts = step["parts"] as? [[String: Any]] {
                    for part in parts {
                        if let type = part["type"] as? String, type == "image",
                           let b64 = part["data"] as? String,
                           let imageData = Data(base64Encoded: b64),
                           let image = UIImage(data: imageData) {
                            return image
                        }
                        if let inlineData = part["inlineData"] as? [String: Any],
                           let b64 = inlineData["data"] as? String,
                           let imageData = Data(base64Encoded: b64),
                           let image = UIImage(data: imageData) {
                            return image
                        }
                    }
                }
            }
        }

        // Shape 2 (SDK convenience): { "output_image": { "data": "<base64>" } }
        if let outputImage = json["output_image"] as? [String: Any],
           let b64 = outputImage["data"] as? String,
           let imageData = Data(base64Encoded: b64),
           let image = UIImage(data: imageData) {
            return image
        }

        // Shape 3: candidates-style (generateContent fallback)
        if let candidates = json["candidates"] as? [[String: Any]],
           let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]] {
            for part in parts {
                if let inlineData = part["inlineData"] as? [String: Any],
                   let b64 = inlineData["data"] as? String,
                   let imageData = Data(base64Encoded: b64),
                   let image = UIImage(data: imageData) {
                    return image
                }
            }
        }

        return nil
    }

    enum ImageGenError: LocalizedError {
        case noKey, badResponse, noImage
        var errorDescription: String? {
            switch self {
            case .noKey: "No Gemini API key configured"
            case .badResponse: "Image generation request failed"
            case .noImage: "No image returned by the model"
            }
        }
    }
}
