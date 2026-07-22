import Foundation

// MARK: - Chat / history (port of lib/history.ts types)

enum ChatRole: String, Codable {
    case user
    case assistant
}

struct ChatMessage: Codable, Equatable, Identifiable {
    var id = UUID()
    var role: ChatRole
    var content: String

    private enum CodingKeys: String, CodingKey {
        case role, content
    }

    init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(ChatRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
    }
}

struct QuizRecord: Codable, Equatable {
    var score: Int
    var total: Int
    var takenAt: Date
}

struct Conversation: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var messages: [ChatMessage]
    var quizzes: [QuizRecord]
    var createdAt: Date
    var updatedAt: Date

    static func title(forFirstMessage firstMessage: String) -> String {
        let firstLine = firstMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")[0]
        return firstLine.count > 80 ? String(firstLine.prefix(80)) + "…" : firstLine
    }
}

// MARK: - Quiz (port of lib/schema.ts)

struct QuizAnswer: Codable, Equatable {
    var text: String
    var isCorrect: Bool
    var whyTempting: String

    private enum CodingKeys: String, CodingKey {
        case text
        case isCorrect = "is_correct"
        case whyTempting = "why_tempting"
    }
}

enum QuizDifficulty: String, Codable {
    case warmup, solid, tricky

    var label: String {
        switch self {
        case .warmup: return "Warm-up"
        case .solid: return "Solid"
        case .tricky: return "Tricky"
        }
    }
}

struct QuizQuestion: Codable, Equatable {
    var conceptTested: String
    var misconception: String
    var question: String
    var hostIntro: String
    var difficulty: QuizDifficulty
    var answers: [QuizAnswer]

    private enum CodingKeys: String, CodingKey {
        case conceptTested = "concept_tested"
        case misconception
        case question
        case hostIntro = "host_intro"
        case difficulty
        case answers
    }

    /// Post-validation: exactly 4 answers, exactly 1 correct.
    func validated() throws -> QuizQuestion {
        guard answers.count == 4 else {
            throw QuizValidationError.badAnswerCount(answers.count)
        }
        let correctCount = answers.filter(\.isCorrect).count
        guard correctCount == 1 else {
            throw QuizValidationError.badCorrectCount(correctCount)
        }
        return self
    }
}

enum QuizValidationError: LocalizedError {
    case badAnswerCount(Int)
    case badCorrectCount(Int)

    var errorDescription: String? {
        switch self {
        case .badAnswerCount(let n): return "Expected 4 answers, got \(n)"
        case .badCorrectCount(let n): return "Expected exactly 1 correct answer, got \(n)"
        }
    }
}

// MARK: - Reading level (port of lib/prompts.ts)

enum ReadingLevel: String, Codable, CaseIterable, Identifiable {
    case elementary, middle, high, university

    var id: String { rawValue }

    var label: String {
        switch self {
        case .elementary: return "Elementary"
        case .middle: return "Middle school"
        case .high: return "High school"
        case .university: return "University"
        }
    }
}

// MARK: - AI provider (port of lib/provider.ts)

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case anthropic
    case gemini
    case openai
    /// Built-in Gemini via Firebase AI — no API key required. Account-bound
    /// and metered (3 free lectures, then Recall Tutor Pro).
    case firebase

    var id: String { rawValue }

    var label: String {
        switch self {
        case .anthropic: return "Claude"
        case .gemini: return "Gemini"
        case .openai: return "OpenAI"
        case .firebase: return "Built-in"
        }
    }
}

// MARK: - Topics (port of lib/topics.ts types)

struct Topic: Equatable, Hashable, Codable {
    var label: String
    var prompt: String
}

enum TopicStatus {
    case partial   // explored but no quiz yet
    case complete  // quiz taken
}
