import Foundation

/// JSON-file-backed conversation history — the iOS counterpart of the web
/// app's localStorage store (lib/history.ts).
struct HistoryStore {
    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("recalltutor_history.json")
    }

    static func load() -> [Conversation] {
        guard let data = try? Data(contentsOf: fileURL),
              let conversations = try? JSONDecoder().decode([Conversation].self, from: data) else {
            return []
        }
        return conversations
    }

    static func save(_ conversations: [Conversation]) {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
