import Foundation

// Gemini REST client — the iOS counterpart of lib/gemini.ts. Optional second
// provider: only active when a Gemini API key is saved in Settings.
//
// Model constants mirror the web app: Gemini 3.5 Flash for content, with
// 2.5 Flash Lite as the fallback when 3.5 is unavailable or failing.
// Reactions stay on Flash Lite deliberately: time-to-first-token matters
// more than model strength there.
enum GeminiModels {
    static let chat = "gemini-3.5-flash"
    static let quizGenerate = "gemini-3.5-flash"
    static let quizReact = "gemini-2.5-flash-lite"
    static let fallback = "gemini-2.5-flash-lite"
}

struct GeminiClient {
    private static let base = "https://generativelanguage.googleapis.com/v1beta/models"

    private static func makeRequest(model: String, action: String, body: [String: Any]) throws -> URLRequest {
        guard let apiKey = Keychain.loadKey(.gemini) else {
            throw AnthropicError.missingAPIKey
        }
        var request = URLRequest(url: URL(string: "\(base)/\(model):\(action)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Run a request against the primary model, retrying once on the
    /// fallback model if the primary fails at request time.
    private static func withFallback<T>(_ primaryModel: String, run: (String) async throws -> T) async throws -> T {
        do {
            return try await run(primaryModel)
        } catch {
            guard primaryModel != GeminiModels.fallback else { throw error }
            return try await run(GeminiModels.fallback)
        }
    }

    /// Extract the concatenated text of the first candidate from a Gemini response chunk.
    private static func candidateText(_ json: [String: Any]) -> String? {
        guard let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return nil }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        return text.isEmpty ? nil : text
    }

    // MARK: - Streaming

    /// POST a streamGenerateContent request and yield text chunks (SSE).
    private static func streamText(model primaryModel: String, body: [String: Any]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await withFallback(primaryModel) { model in
                        let request = try makeRequest(model: model, action: "streamGenerateContent?alt=sse", body: body)
                        let (bytes, response) = try await URLSession.shared.bytes(for: request)
                        guard let http = response as? HTTPURLResponse else { throw AnthropicError.badResponse }
                        guard http.statusCode == 200 else {
                            var errorData = Data()
                            for try await byte in bytes { errorData.append(byte) }
                            throw AnthropicError.from(status: http.statusCode, body: errorData)
                        }
                        for try await line in bytes.lines {
                            guard line.hasPrefix("data: ") else { continue }
                            guard let data = line.dropFirst(6).data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                            if let text = candidateText(json) {
                                continuation.yield(text)
                            }
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

    static func streamChat(messages: [ChatMessage], readingLevel: ReadingLevel) -> AsyncThrowingStream<String, Error> {
        let body: [String: Any] = [
            "contents": messages.map {
                [
                    "role": $0.role == .assistant ? "model" : "user",
                    "parts": [["text": $0.content]],
                ]
            },
            "systemInstruction": ["parts": [["text": Prompts.chatSystemPrompt(level: readingLevel)]]],
        ]
        return streamText(model: GeminiModels.chat, body: body)
    }

    // MARK: - Quiz generation (responseSchema)

    /// Gemini responseSchema for quiz questions — port of GEMINI_QUIZ_QUESTION_SCHEMA.
    private static let quizQuestionSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "concept_tested": ["type": "STRING", "description": "The single claim from the explanation this question tests"],
            "misconception": ["type": "STRING", "description": "The specific plausible misconception this question targets"],
            "question": ["type": "STRING", "description": "Max 25 words. Tests understanding, not verbatim recall of phrasing."],
            "host_intro": ["type": "STRING", "description": "One-line setup for this question, max 15 words"],
            "difficulty": ["type": "STRING", "enum": ["warmup", "solid", "tricky"]],
            "answers": [
                "type": "ARRAY",
                "description": "Exactly 4 items. Exactly one has is_correct=true.",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "text": ["type": "STRING", "description": "Max 8 words"],
                        "is_correct": ["type": "BOOLEAN"],
                        "why_tempting": ["type": "STRING", "description": "Why a learner would pick this. For the correct answer: why it is right."],
                    ],
                    "required": ["text", "is_correct", "why_tempting"],
                ],
            ],
        ],
        "required": ["concept_tested", "misconception", "question", "host_intro", "difficulty", "answers"],
    ]

    static func generateQuizQuestion(
        transcript: String,
        difficulty: QuizDifficulty,
        readingLevel: ReadingLevel,
        previousQuestions: [String]
    ) async throws -> QuizQuestion {
        let body: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": Prompts.quizGenerationUserPrompt(transcript: transcript, previousQuestions: previousQuestions)]],
                ]
            ],
            "systemInstruction": ["parts": [["text": Prompts.quizGenerationSystemPrompt(difficulty: difficulty, level: readingLevel)]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": quizQuestionSchema,
            ],
        ]

        return try await withFallback(GeminiModels.quizGenerate) { model in
            let request = try makeRequest(model: model, action: "generateContent", body: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AnthropicError.badResponse }
            guard http.statusCode == 200 else {
                throw AnthropicError.from(status: http.statusCode, body: data)
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = candidateText(json),
                  let questionData = text.data(using: .utf8) else {
                throw AnthropicError.badResponse
            }
            var question = try JSONDecoder().decode(QuizQuestion.self, from: questionData).validated()
            question.answers.shuffle()
            return question
        }
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
            "contents": [
                [
                    "role": "user",
                    "parts": [[
                        "text": Prompts.reactUserPrompt(
                            question: question,
                            chosen: chosen,
                            correct: correct,
                            wasCorrect: wasCorrect,
                            streak: streak,
                            responseTimeSeconds: responseTimeSeconds
                        )
                    ]],
                ]
            ],
            "systemInstruction": ["parts": [["text": Prompts.professorSystemPrompt]]],
        ]
        return streamText(model: GeminiModels.quizReact, body: body)
    }

    // MARK: - Topic generation

    private static let topicsSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "topics": [
                "type": "ARRAY",
                "description": "A list of 8 topics generated for the user.",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "label": ["type": "STRING", "description": "Short label, max 3 words"],
                        "prompt": ["type": "STRING", "description": "The exact prompt/question to ask the tutor"]
                    ],
                    "required": ["label", "prompt"]
                ]
            ]
        ],
        "required": ["topics"]
    ]

    static func generateTopics(
        category: String,
        readingLevel: ReadingLevel,
        excluding: Set<String>
    ) async throws -> [Topic] {
        let body: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": Prompts.topicGenerationUserPrompt(excluding: excluding)]]
                ]
            ],
            "systemInstruction": ["parts": [["text": Prompts.topicGenerationSystemPrompt(category: category, level: readingLevel)]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": topicsSchema
            ]
        ]

        struct ResponseEnvelope: Decodable {
            var topics: [Topic]
        }

        return try await withFallback(GeminiModels.chat) { model in
            let request = try makeRequest(model: model, action: "generateContent", body: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AnthropicError.badResponse }
            guard http.statusCode == 200 else {
                throw AnthropicError.from(status: http.statusCode, body: data)
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = candidateText(json),
                  let topicsData = text.data(using: .utf8) else {
                throw AnthropicError.badResponse
            }
            let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: topicsData)
            return envelope.topics
        }
    }
}

// MARK: - Provider dispatch

/// Unified facade that routes each call to the selected provider —
/// the iOS counterpart of lib/provider.ts.
enum AIService {
    static func availableProviders() -> [AIProvider] {
        var providers: [AIProvider] = []
        if Keychain.loadKey(.anthropic) != nil { providers.append(.anthropic) }
        if Keychain.loadKey(.gemini) != nil { providers.append(.gemini) }
        // Built-in tier: available whenever the app ships Firebase config;
        // sign-in and metering are enforced at generation time.
        if FirebaseAIClient.isAvailable { providers.append(.firebase) }
        return providers
    }

    static func streamChat(provider: AIProvider, messages: [ChatMessage], readingLevel: ReadingLevel) -> AsyncThrowingStream<String, Error> {
        switch provider {
        case .anthropic: AnthropicClient.streamChat(messages: messages, readingLevel: readingLevel)
        case .gemini: GeminiClient.streamChat(messages: messages, readingLevel: readingLevel)
        case .firebase: FirebaseAIClient.streamChat(messages: messages, readingLevel: readingLevel)
        }
    }

    static func generateQuizQuestion(
        provider: AIProvider,
        transcript: String,
        difficulty: QuizDifficulty,
        readingLevel: ReadingLevel,
        previousQuestions: [String]
    ) async throws -> QuizQuestion {
        switch provider {
        case .anthropic:
            try await AnthropicClient.generateQuizQuestion(
                transcript: transcript, difficulty: difficulty,
                readingLevel: readingLevel, previousQuestions: previousQuestions
            )
        case .gemini:
            try await GeminiClient.generateQuizQuestion(
                transcript: transcript, difficulty: difficulty,
                readingLevel: readingLevel, previousQuestions: previousQuestions
            )
        case .firebase:
            try await FirebaseAIClient.generateQuizQuestion(
                transcript: transcript, difficulty: difficulty,
                readingLevel: readingLevel, previousQuestions: previousQuestions
            )
        }
    }

    static func streamReaction(
        provider: AIProvider,
        question: String,
        chosen: QuizAnswer,
        correct: QuizAnswer,
        wasCorrect: Bool,
        streak: Int,
        responseTimeSeconds: Double
    ) -> AsyncThrowingStream<String, Error> {
        switch provider {
        case .anthropic:
            AnthropicClient.streamReaction(
                question: question, chosen: chosen, correct: correct,
                wasCorrect: wasCorrect, streak: streak, responseTimeSeconds: responseTimeSeconds
            )
        case .gemini:
            GeminiClient.streamReaction(
                question: question, chosen: chosen, correct: correct,
                wasCorrect: wasCorrect, streak: streak, responseTimeSeconds: responseTimeSeconds
            )
        case .firebase:
            FirebaseAIClient.streamReaction(
                question: question, chosen: chosen, correct: correct,
                wasCorrect: wasCorrect, streak: streak, responseTimeSeconds: responseTimeSeconds
            )
        }
    }

    static func generateTopics(
        provider: AIProvider,
        category: String,
        readingLevel: ReadingLevel,
        excluding: Set<String>
    ) async throws -> [Topic] {
        switch provider {
        case .anthropic:
            try await AnthropicClient.generateTopics(
                category: category, readingLevel: readingLevel, excluding: excluding
            )
        case .gemini:
            try await GeminiClient.generateTopics(
                category: category, readingLevel: readingLevel, excluding: excluding
            )
        case .firebase:
            try await FirebaseAIClient.generateTopics(
                category: category, readingLevel: readingLevel, excluding: excluding
            )
        }
    }
}
