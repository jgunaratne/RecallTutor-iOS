import Foundation
import SwiftUI

// Topic mastery model — port of lib/mastery.ts. A "topic" is a conversation:
// its lecture cards are what the user studied, and its quiz records are the
// evidence of recall. Mastery is driven by recency-weighted quiz accuracy.

enum MasteryLevel: Int, Comparable {
    case notStarted, learning, developing, proficient, mastered

    static func < (lhs: MasteryLevel, rhs: MasteryLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .notStarted: return "Not started"
        case .learning: return "Learning"
        case .developing: return "Developing"
        case .proficient: return "Proficient"
        case .mastered: return "Mastered"
        }
    }

    var textColor: Color {
        switch self {
        case .notStarted, .learning: return Theme.textTertiary
        case .developing: return Theme.amberText
        case .proficient, .mastered: return Theme.correctText
        }
    }

    var fillColor: Color {
        switch self {
        case .notStarted: return Theme.borderSubtle
        case .learning: return Theme.accent.opacity(0.6)
        case .developing: return Theme.amberBar
        case .proficient: return Theme.emeraldBar
        case .mastered: return Theme.correctBorder
        }
    }
}

enum MasteryTrend {
    case improving, slipping, steady
}

struct TopicMastery {
    var level: MasteryLevel
    /// 0..1 — fills the progress ring/bar.
    var score: Double
    /// Recency-weighted quiz accuracy (0..1), or nil before the first quiz.
    var accuracy: Double?
    var quizzesTaken: Int
    var cardsStudied: Int
    /// Number of lectures the topic spans — grows with each deep dive.
    var depth: Int
    var trend: MasteryTrend?
    /// Learner-facing guidance: what the level means and what to do next.
    var feedback: String
}

enum Mastery {
    // A topic is mastered when accuracy holds up across repeated quizzes.
    private static let masteredMinQuizzes = 2
    private static let masteredMinAccuracy = 0.85
    private static let masteredMinLastQuiz = 0.8

    static func compute(for conversation: Conversation) -> TopicMastery {
        let assistantMessages = conversation.messages.filter { $0.role == .assistant }
        let cardsStudied = assistantMessages.reduce(0) { $0 + CardSplitter.splitIntoCards($1.content).count }
        let depth = assistantMessages.count

        let ratios = conversation.quizzes
            .filter { $0.total > 0 }
            .map { Double($0.score) / Double($0.total) }
        let quizzesTaken = ratios.count

        // Recency-weighted accuracy: quiz i gets weight i+1.
        var accuracy: Double?
        if quizzesTaken > 0 {
            var weighted = 0.0
            var totalWeight = 0.0
            for (i, r) in ratios.enumerated() {
                let w = Double(i + 1)
                weighted += r * w
                totalWeight += w
            }
            accuracy = weighted / totalWeight
        }

        let lastRatio = ratios.last
        let prevRatio = quizzesTaken > 1 ? ratios[quizzesTaken - 2] : nil
        var trend: MasteryTrend?
        if let last = lastRatio, let prev = prevRatio {
            trend = last > prev ? .improving : last < prev ? .slipping : .steady
        }

        let level: MasteryLevel
        if let acc = accuracy {
            if quizzesTaken >= masteredMinQuizzes,
               acc >= masteredMinAccuracy,
               (lastRatio ?? 0) >= masteredMinLastQuiz {
                level = .mastered
            } else if acc >= 0.8 {
                level = .proficient
            } else if acc >= 0.5 {
                level = .developing
            } else {
                level = .learning
            }
        } else {
            level = cardsStudied > 0 ? .learning : .notStarted
        }

        // Ring fill: before any quiz, studying alone fills a sliver; after
        // that, accuracy drives it, discounted until a second quiz confirms.
        var score: Double
        if let acc = accuracy {
            let consistency = min(1, Double(quizzesTaken) / Double(masteredMinQuizzes))
            score = acc * (0.7 + 0.3 * consistency)
        } else {
            score = min(0.2, Double(cardsStudied) * 0.02)
        }
        if level == .mastered { score = 1 }

        return TopicMastery(
            level: level,
            score: score,
            accuracy: accuracy,
            quizzesTaken: quizzesTaken,
            cardsStudied: cardsStudied,
            depth: depth,
            trend: trend,
            feedback: buildFeedback(
                level: level, accuracy: accuracy, quizzesTaken: quizzesTaken,
                cardsStudied: cardsStudied, depth: depth, trend: trend
            )
        )
    }

    private static func buildFeedback(
        level: MasteryLevel,
        accuracy: Double?,
        quizzesTaken: Int,
        cardsStudied: Int,
        depth: Int,
        trend: MasteryTrend?
    ) -> String {
        let pct = accuracy.map { Int(($0 * 100).rounded()) }

        switch level {
        case .notStarted:
            return "Ask a question to start studying this topic."
        case .learning:
            if quizzesTaken == 0 {
                return "\(cardsStudied) card\(cardsStudied == 1 ? "" : "s") studied — take a pop quiz to start building mastery."
            }
            if trend == .slipping {
                return "Slipping — your last quiz dropped. Reread the cards before trying again."
            }
            return "Needs review — accuracy is at \(pct ?? 0)%. Reread the cards, then retake the quiz."
        case .developing:
            if trend == .improving {
                return "Improving — your last quiz was your best yet. Keep quizzing to reach proficiency."
            }
            if trend == .slipping {
                return "Slipping — your last quiz dropped. Review the cards to regain ground."
            }
            return "Developing — \(pct ?? 0)% accuracy. Review what you missed, then quiz again."
        case .proficient:
            if quizzesTaken < masteredMinQuizzes {
                return "Strong start — one more strong quiz confirms mastery."
            }
            return "So close — score \(Int(masteredMinLastQuiz * 100))%+ on your next quiz to reach mastery."
        case .mastered:
            if depth > 1 {
                return "Mastered at \(pct ?? 0)% accuracy — and it held across \(depth) deep dives."
            }
            return "Mastered at \(pct ?? 0)% accuracy. Go deeper to stretch it further."
        }
    }
}
