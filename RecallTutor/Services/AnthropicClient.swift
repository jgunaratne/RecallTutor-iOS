import Foundation

// Direct Claude Messages API client over HTTPS (no SDK is published for
// Swift). Mirrors the recall-deck server routes: streaming chat lectures,
// quiz generation via structured outputs, and streamed answer feedback.
//
// Models match the web app: Sonnet 4.6 for lectures + quiz generation,
// Haiku 4.5 for the short feedback reactions.
enum Models {
    static let chat = "claude-sonnet-4-6"
    static let quizGenerate = "claude-sonnet-4-6"
    static let quizReact = "claude-haiku-4-5"
}

enum AnthropicError: LocalizedError {
    case missingAPIKey
    case badResponse
    case api(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key set. Add your Anthropic API key in Settings (sidebar → Settings)."
        case .badResponse:
            return "Something went wrong while generating a response. Please try again."
        case .api(let status, let message):
            _ = status
            return message
        }
    }

    /// Map HTTP status codes to user-presentable messages, mirroring the
    /// web app's describeChatError.
    static func from(status: Int, body: Data?) -> AnthropicError {
        switch status {
        case 503, 529:
            return .api(status: status, message: "The AI model is experiencing high demand right now. This is usually temporary — try again in a moment.")
        case 429:
            return .api(status: status, message: "Rate limit reached. Wait a few seconds and try again.")
        case 401, 403:
            return .api(status: status, message: "The AI provider rejected the API key — check it in Settings.")
        default:
            // Surface the API's own message for request errors when available.
            if let body,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return .api(status: status, message: message)
            }
            return .api(status: status, message: "Something went wrong while generating a response. Please try again.")
        }
    }
}

struct AnthropicClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private static func makeRequest(body: [String: Any]) throws -> URLRequest {
        guard let apiKey = Keychain.loadAPIKey() else {
            throw AnthropicError.missingAPIKey
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Streaming (SSE)

    /// POST a streaming Messages request and yield text deltas as they arrive.
    private static func streamText(body: [String: Any]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var streamBody = body
                    streamBody["stream"] = true
                    let request = try makeRequest(body: streamBody)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw AnthropicError.badResponse
                    }
                    guard http.statusCode == 200 else {
                        // Read the error body (small) for a useful message.
                        var errorData = Data()
                        for try await byte in bytes { errorData.append(byte) }
                        throw AnthropicError.from(status: http.statusCode, body: errorData)
                    }

                    // Parse SSE: lines of "event: ..." / "data: {...}"
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = line.dropFirst(6)
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = json["type"] as? String else { continue }

                        if type == "content_block_delta",
                           let delta = json["delta"] as? [String: Any],
                           delta["type"] as? String == "text_delta",
                           let text = delta["text"] as? String {
                            continuation.yield(text)
                        } else if type == "error" {
                            let message = (json["error"] as? [String: Any])?["message"] as? String
                            throw AnthropicError.api(status: 500, message: message ?? "Stream error")
                        } else if type == "message_stop" {
                            break
                        }
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

    /// Stream a tutor lecture for the conversation so far.
    static func streamChat(messages: [ChatMessage], readingLevel: ReadingLevel) -> AsyncThrowingStream<String, Error> {
        var apiMessages: [[String: Any]] = messages.map {
            ["role": $0.role.rawValue, "content": $0.content]
        }
        // Prompt caching: breakpoint on the last message block so follow-up
        // turns in the same conversation reuse the growing prefix.
        if !apiMessages.isEmpty {
            let last = apiMessages.count - 1
            apiMessages[last]["content"] = [
                [
                    "type": "text",
                    "text": messages[last].content,
                    "cache_control": ["type": "ephemeral"],
                ]
            ]
        }

        let body: [String: Any] = [
            "model": Models.chat,
            // Lectures are token-hungry; streaming, so no timeout risk.
            "max_tokens": 8192,
            "system": [
                [
                    "type": "text",
                    "text": Prompts.chatSystemPrompt(level: readingLevel),
                    "cache_control": ["type": "ephemeral"],
                ]
            ],
            "messages": apiMessages,
        ]
        return streamText(body: body)
    }

    // MARK: - Quiz generation (structured outputs)

    /// JSON Schema for quiz questions — port of QUIZ_QUESTION_JSON_SCHEMA.
    private static let quizQuestionSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "concept_tested": ["type": "string", "description": "The single claim from the explanation this question tests"],
            "misconception": ["type": "string", "description": "The specific plausible misconception this question targets"],
            "question": ["type": "string", "description": "Max 25 words. Tests understanding, not verbatim recall of phrasing."],
            "host_intro": ["type": "string", "description": "One-line setup for this question, max 15 words"],
            "difficulty": ["type": "string", "enum": ["warmup", "solid", "tricky"]],
            "answers": [
                "type": "array",
                "description": "Exactly 4 items. Exactly one has is_correct=true.",
                "items": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string", "description": "Max 8 words"],
                        "is_correct": ["type": "boolean"],
                        "why_tempting": ["type": "string", "description": "Why a learner would pick this. For the correct answer: why it is right."],
                    ],
                    "required": ["text", "is_correct", "why_tempting"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["concept_tested", "misconception", "question", "host_intro", "difficulty", "answers"],
        "additionalProperties": false,
    ]

    /// Generate one validated multiple-choice question grounded in a lecture card.
    static func generateQuizQuestion(
        transcript: String,
        difficulty: QuizDifficulty,
        readingLevel: ReadingLevel,
        previousQuestions: [String]
    ) async throws -> QuizQuestion {
        let body: [String: Any] = [
            "model": Models.quizGenerate,
            "max_tokens": 1024,
            "system": Prompts.quizGenerationSystemPrompt(difficulty: difficulty, level: readingLevel),
            "messages": [
                [
                    "role": "user",
                    "content": Prompts.quizGenerationUserPrompt(transcript: transcript, previousQuestions: previousQuestions),
                ]
            ],
            "output_config": [
                "format": [
                    "type": "json_schema",
                    "schema": quizQuestionSchema,
                ]
            ],
        ]

        let request = try makeRequest(body: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AnthropicError.badResponse }
        guard http.statusCode == 200 else {
            throw AnthropicError.from(status: http.statusCode, body: data)
        }

        // Extract the first text block — with output_config.format it holds valid JSON.
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let textBlock = content.first(where: { $0["type"] as? String == "text" }),
              let text = textBlock["text"] as? String,
              let questionData = text.data(using: .utf8) else {
            throw AnthropicError.badResponse
        }

        var question = try JSONDecoder().decode(QuizQuestion.self, from: questionData).validated()
        // Shuffle answers client-side to defeat LLM position bias.
        question.answers.shuffle()
        return question
    }

    // MARK: - Answer feedback reaction

    /// Stream the short feedback reaction to the student's answer.
    static func streamReaction(
        question: String,
        chosen: QuizAnswer,
        correct: QuizAnswer,
        wasCorrect: Bool,
        streak: Int,
        responseTimeSeconds: Double
    ) -> AsyncThrowingStream<String, Error> {
        let body: [String: Any] = [
            "model": Models.quizReact,
            "max_tokens": 256,
            "system": Prompts.professorSystemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": Prompts.reactUserPrompt(
                        question: question,
                        chosen: chosen,
                        correct: correct,
                        wasCorrect: wasCorrect,
                        streak: streak,
                        responseTimeSeconds: responseTimeSeconds
                    ),
                ]
            ],
        ]
        return streamText(body: body)
    }
}
