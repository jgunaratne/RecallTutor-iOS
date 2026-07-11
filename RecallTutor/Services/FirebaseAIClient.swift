import FirebaseAI
import FirebaseCore
import Foundation

/// Errors from the built-in (Firebase-managed) AI tier.
enum ManagedAIError: LocalizedError {
    case notConfigured
    case signInRequired
    case subscriptionRequired
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "The built-in tutor isn't set up. Add your own API key in Settings."
        case .signInRequired:
            return "Sign in with Google to use the built-in tutor, or add your own API key in Settings."
        case .subscriptionRequired:
            return "You've used your \(SubscriptionManager.freeLectureLimit) free lectures. Subscribe to Pro or add your own API key in Settings."
        case .emptyResponse:
            return "The tutor returned an empty response. Please try again."
        }
    }
}

/// Firebase AI (managed Gemini) client — the no-API-key counterpart of
/// GeminiClient, following podchat's ModelPreferences Firebase path. Only
/// active when the app is configured with a GoogleService-Info.plist and the
/// user is signed in; usage is metered by SubscriptionManager.
enum FirebaseAIClient {
    /// Whether the Firebase-managed tier can be used at all on this build
    /// (GoogleService-Info.plist present → FirebaseApp configured at launch).
    static var isAvailable: Bool { FirebaseApp.app() != nil }

    /// Build a generative model on the Gemini Developer API backend.
    private static func model(
        name: String,
        systemPrompt: String,
        config: GenerationConfig? = nil
    ) -> GenerativeModel {
        FirebaseAI.firebaseAI(backend: .googleAI()).generativeModel(
            modelName: name,
            generationConfig: config,
            systemInstruction: ModelContent(role: "system", parts: systemPrompt)
        )
    }

    /// Map chat history to Gemini content turns.
    private static func contents(_ messages: [ChatMessage]) -> [ModelContent] {
        messages.map {
            ModelContent(role: $0.role == .assistant ? "model" : "user", parts: $0.content)
        }
    }

    /// Adapt a FirebaseAI response stream to the app's plain-text stream shape.
    private static func textStream(
        model: GenerativeModel,
        contents: [ModelContent]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = try model.generateContentStream(contents)
                    for try await chunk in stream {
                        if let text = chunk.text, !text.isEmpty {
                            continuation.yield(text)
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
        let model = model(
            name: GeminiModels.chat,
            systemPrompt: Prompts.chatSystemPrompt(level: readingLevel)
        )
        return textStream(model: model, contents: contents(messages))
    }

    // MARK: - Quiz generation (responseSchema)

    /// FirebaseAI Schema mirror of GeminiClient's quiz question schema.
    private static let quizQuestionSchema: Schema = .object(
        properties: [
            "concept_tested": .string(description: "The single claim from the explanation this question tests"),
            "misconception": .string(description: "The specific plausible misconception this question targets"),
            "question": .string(description: "Max 25 words. Tests understanding, not verbatim recall of phrasing."),
            "host_intro": .string(description: "One-line setup for this question, max 15 words"),
            "difficulty": .enumeration(values: ["warmup", "solid", "tricky"]),
            "answers": .array(
                items: .object(
                    properties: [
                        "text": .string(description: "Max 8 words"),
                        "is_correct": .boolean(),
                        "why_tempting": .string(description: "Why a learner would pick this. For the correct answer: why it is right."),
                    ]
                ),
                description: "Exactly 4 items. Exactly one has is_correct=true."
            ),
        ]
    )

    static func generateQuizQuestion(
        transcript: String,
        difficulty: QuizDifficulty,
        readingLevel: ReadingLevel,
        previousQuestions: [String]
    ) async throws -> QuizQuestion {
        let model = model(
            name: GeminiModels.quizGenerate,
            systemPrompt: Prompts.quizGenerationSystemPrompt(difficulty: difficulty, level: readingLevel),
            config: GenerationConfig(
                responseMIMEType: "application/json",
                responseSchema: quizQuestionSchema
            )
        )

        let response = try await model.generateContent(
            Prompts.quizGenerationUserPrompt(transcript: transcript, previousQuestions: previousQuestions)
        )
        guard let text = response.text, let data = text.data(using: .utf8) else {
            throw ManagedAIError.emptyResponse
        }
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
        let model = model(
            name: GeminiModels.quizReact,
            systemPrompt: Prompts.professorSystemPrompt
        )
        let prompt = Prompts.reactUserPrompt(
            question: question,
            chosen: chosen,
            correct: correct,
            wasCorrect: wasCorrect,
            streak: streak,
            responseTimeSeconds: responseTimeSeconds
        )
        return textStream(model: model, contents: [ModelContent(role: "user", parts: prompt)])
    }

    // MARK: - Topic generation

    private static let topicsSchema: Schema = .object(
        properties: [
            "topics": .array(
                items: .object(
                    properties: [
                        "label": .string(description: "Short label, max 3 words"),
                        "prompt": .string(description: "The exact prompt/question to ask the tutor")
                    ]
                ),
                description: "A list of 8 topics generated for the user."
            )
        ]
    )

    static func generateTopics(
        category: String,
        readingLevel: ReadingLevel,
        excluding: Set<String>
    ) async throws -> [Topic] {
        let model = model(
            name: GeminiModels.chat,
            systemPrompt: Prompts.topicGenerationSystemPrompt(category: category, level: readingLevel),
            config: GenerationConfig(
                responseMIMEType: "application/json",
                responseSchema: topicsSchema
            )
        )

        struct ResponseEnvelope: Decodable {
            var topics: [Topic]
        }

        let response = try await model.generateContent(
            Prompts.topicGenerationUserPrompt(excluding: excluding)
        )
        guard let text = response.text, let data = text.data(using: .utf8) else {
            throw ManagedAIError.emptyResponse
        }
        let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        return envelope.topics
    }
}
