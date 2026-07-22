import Foundation

/// Direct OpenAI Chat Completions client over HTTPS. This app already keeps
/// provider keys in the Keychain and talks directly to Anthropic and Gemini,
/// so OpenAI follows the same user-owned-key model.
enum OpenAIModels {
    /// Balanced model for longer tutor lectures and structured quiz prompts.
    static let chat = "gpt-5.6-terra"
    static let quizGenerate = "gpt-5.6-terra"
    /// Cost-sensitive model for short quiz reactions and topic suggestions.
    static let quizReact = "gpt-5.6-luna"
    static let topics = "gpt-5.6-luna"
    /// Educational card illustrations use the dedicated GPT Image endpoint.
    static let image = "gpt-image-2"
}

enum OpenAIError: LocalizedError {
    case missingAPIKey
    case badResponse
    case api(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key set. Add your OpenAI API key in Settings."
        case .badResponse:
            return "Something went wrong while generating a response. Please try again."
        case .api(_, let message):
            return message
        }
    }

    static func from(status: Int, body: Data?) -> OpenAIError {
        let providerMessage: String? = {
            guard let body,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let error = json["error"] as? [String: Any] else { return nil }
            return error["message"] as? String
        }()

        if status == 429,
           let providerMessage,
           providerMessage.localizedCaseInsensitiveContains("quota") {
            return .api(
                status: status,
                message: "The OpenAI account has no available API quota. Check billing and project limits, then try again."
            )
        }
        switch status {
        case 503, 529:
            return .api(status: status, message: "The AI model is experiencing high demand right now. This is usually temporary — try again in a moment.")
        case 429:
            return .api(status: status, message: "Rate limit reached. Wait a few seconds and try again.")
        case 401, 403:
            return .api(status: status, message: "The AI provider rejected the API key — check it in Settings.")
        default:
            return .api(status: status, message: providerMessage ?? "Something went wrong while generating a response. Please try again.")
        }
    }
}

struct OpenAIClient {
    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let imageGenerationEndpoint = URL(string: "https://api.openai.com/v1/images/generations")!

    private static func makeRequest(body: [String: Any]) throws -> URLRequest {
        guard let apiKey = Keychain.loadKey(.openai) else {
            throw OpenAIError.missingAPIKey
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func apiMessages(_ messages: [ChatMessage]) -> [[String: String]] {
        messages.map { ["role": $0.role.rawValue, "content": $0.content] }
    }

    // MARK: - Streaming

    private static func streamText(body: [String: Any]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var streamBody = body
                    streamBody["stream"] = true
                    let request = try makeRequest(body: streamBody)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw OpenAIError.badResponse
                    }
                    guard http.statusCode == 200 else {
                        var errorData = Data()
                        for try await byte in bytes { errorData.append(byte) }
                        throw OpenAIError.from(status: http.statusCode, body: errorData)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = line.dropFirst(6)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }
                        if let error = json["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            throw OpenAIError.api(status: 500, message: message)
                        }
                        guard let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let text = delta["content"] as? String,
                              !text.isEmpty else { continue }
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Chat lecture

    static func streamChat(messages: [ChatMessage], readingLevel: ReadingLevel) -> AsyncThrowingStream<String, Error> {
        let body: [String: Any] = [
            "model": OpenAIModels.chat,
            "max_completion_tokens": 8192,
            "messages": [[
                "role": "system",
                "content": Prompts.chatSystemPrompt(level: readingLevel),
            ]] + apiMessages(messages),
        ]
        return streamText(body: body)
    }

    // MARK: - Structured quiz generation

    private static let quizQuestionSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "concept_tested": ["type": "string"],
            "misconception": ["type": "string"],
            "question": ["type": "string"],
            "host_intro": ["type": "string"],
            "difficulty": ["type": "string", "enum": ["warmup", "solid", "tricky"]],
            "answers": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string"],
                        "is_correct": ["type": "boolean"],
                        "why_tempting": ["type": "string"],
                    ],
                    "required": ["text", "is_correct", "why_tempting"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["concept_tested", "misconception", "question", "host_intro", "difficulty", "answers"],
        "additionalProperties": false,
    ]

    private static func structuredText(body: [String: Any]) async throws -> String {
        let request = try makeRequest(body: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.badResponse }
        guard http.statusCode == 200 else {
            throw OpenAIError.from(status: http.statusCode, body: data)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.badResponse
        }
        return content
    }

    private static func jsonSchema(name: String, schema: [String: Any]) -> [String: Any] {
        [
            "type": "json_schema",
            "json_schema": [
                "name": name,
                "strict": true,
                "schema": schema,
            ],
        ]
    }

    static func generateQuizQuestion(
        transcript: String,
        difficulty: QuizDifficulty,
        readingLevel: ReadingLevel,
        previousQuestions: [String]
    ) async throws -> QuizQuestion {
        let body: [String: Any] = [
            "model": OpenAIModels.quizGenerate,
            "max_completion_tokens": 1024,
            "response_format": jsonSchema(name: "quiz_question", schema: quizQuestionSchema),
            "messages": [
                ["role": "system", "content": Prompts.quizGenerationSystemPrompt(difficulty: difficulty, level: readingLevel)],
                ["role": "user", "content": Prompts.quizGenerationUserPrompt(transcript: transcript, previousQuestions: previousQuestions)],
            ],
        ]
        let content = try await structuredText(body: body)
        guard let data = content.data(using: .utf8) else { throw OpenAIError.badResponse }
        var question = try JSONDecoder().decode(QuizQuestion.self, from: data).validated()
        question.answers.shuffle()
        return question
    }

    // MARK: - Answer feedback reaction

    static func streamReaction(
        question: String,
        chosen: QuizAnswer,
        correct: QuizAnswer,
        wasCorrect: Bool,
        streak: Int,
        responseTimeSeconds: Double
    ) -> AsyncThrowingStream<String, Error> {
        let body: [String: Any] = [
            "model": OpenAIModels.quizReact,
            "max_completion_tokens": 256,
            "messages": [
                ["role": "system", "content": Prompts.professorSystemPrompt],
                [
                    "role": "user",
                    "content": Prompts.reactUserPrompt(
                        question: question, chosen: chosen, correct: correct,
                        wasCorrect: wasCorrect, streak: streak,
                        responseTimeSeconds: responseTimeSeconds
                    ),
                ],
            ],
        ]
        return streamText(body: body)
    }

    // MARK: - Topic generation

    private static let topicsSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "topics": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "label": ["type": "string"],
                        "prompt": ["type": "string"],
                    ],
                    "required": ["label", "prompt"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["topics"],
        "additionalProperties": false,
    ]

    static func generateTopics(
        category: String,
        readingLevel: ReadingLevel,
        excluding: Set<String>
    ) async throws -> [Topic] {
        struct ResponseEnvelope: Decodable {
            var topics: [Topic]
        }

        let body: [String: Any] = [
            "model": OpenAIModels.topics,
            "max_completion_tokens": 1024,
            "response_format": jsonSchema(name: "topic_suggestions", schema: topicsSchema),
            "messages": [
                ["role": "system", "content": Prompts.topicGenerationSystemPrompt(category: category, level: readingLevel)],
                ["role": "user", "content": Prompts.topicGenerationUserPrompt(excluding: excluding)],
            ],
        ]
        let content = try await structuredText(body: body)
        guard let data = content.data(using: .utf8) else { throw OpenAIError.badResponse }
        return try JSONDecoder().decode(ResponseEnvelope.self, from: data).topics
    }

    // MARK: - Image generation

    /// Generate a landscape card illustration through the Image API.  The
    /// endpoint returns base64 image bytes, which keeps the user-owned key and
    /// generated asset entirely on-device.
    static func generateImage(prompt: String) async throws -> Data {
        guard let apiKey = Keychain.loadKey(.openai) else {
            throw OpenAIError.missingAPIKey
        }

        let body: [String: Any] = [
            "model": OpenAIModels.image,
            "prompt": prompt,
            "size": "1536x1024",
            "quality": "low",
            "output_format": "png",
        ]
        var request = URLRequest(url: imageGenerationEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.badResponse }
        guard http.statusCode == 200 else {
            throw OpenAIError.from(status: http.statusCode, body: data)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = json["data"] as? [[String: Any]],
              let encoded = images.first?["b64_json"] as? String,
              let image = Data(base64Encoded: encoded) else {
            throw OpenAIError.badResponse
        }
        return image
    }
}
