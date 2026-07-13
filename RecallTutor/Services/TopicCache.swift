import Foundation

/// Persists the last AI-generated topic chips to disk so the home screen
/// can display them instantly on next launch instead of showing shimmers
/// while waiting for a fresh AI round-trip.
struct TopicCache {
    /// What we store: the topics keyed by category, plus the reading level
    /// they were generated for (so a level change invalidates the cache).
    private struct Snapshot: Codable {
        var readingLevel: ReadingLevel
        var topics: [String: [Topic]]   // TopicCategory.rawValue → topics
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("recalltutor_topic_cache.json")
    }

    /// Returns cached topics if they exist and match the given reading level.
    static func load(for level: ReadingLevel) -> [TopicCategory: [Topic]]? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.readingLevel == level else {
            return nil
        }
        // Re-key from String → TopicCategory
        var result: [TopicCategory: [Topic]] = [:]
        for (key, topics) in snapshot.topics {
            if let category = TopicCategory(rawValue: key) {
                result[category] = topics
            }
        }
        return result.isEmpty ? nil : result
    }

    /// Persist the current topic set alongside the reading level.
    static func save(_ topics: [TopicCategory: [Topic]], level: ReadingLevel) {
        // Key by rawValue for stable JSON keys
        var mapped: [String: [Topic]] = [:]
        for (category, list) in topics {
            mapped[category.rawValue] = list
        }
        let snapshot = Snapshot(readingLevel: level, topics: mapped)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
