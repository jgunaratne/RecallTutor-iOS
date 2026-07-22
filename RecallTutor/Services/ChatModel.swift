import Foundation
import Observation

/// Central app state — the iOS counterpart of the web app's Chat component
/// state plus the localStorage-backed history store.
@Observable
@MainActor
final class ChatModel {
    // Conversation state
    var messages: [ChatMessage] = []
    var isStreaming = false
    var errorMessage: String?
    var showQuizButton = false

    // History
    var conversations: [Conversation] = []
    var activeId: UUID?

    // Quiz takeover
    var quizSource: QuizSource?
    var masteryNote: MasteryNote?

    // Realtime voice tutor — one session per lecture when a Gemini or OpenAI
    // key is configured (mirrors the web app's mount-per-last-message).
    var voiceTutor: VoiceTutorManager?

    // Settings
    var readingLevel: ReadingLevel {
        didSet {
            UserDefaults.standard.set(readingLevel.rawValue, forKey: "recalltutor_reading_level")
            topicLoadTask?.cancel()
            topicLoadTask = Task {
                await loadInitialTopics()
            }
        }
    }
    var provider: AIProvider {
        didSet {
            // An OpenAI key is an app-wide provider choice, not merely an
            // optional entry in the picker: it governs text, realtime audio,
            // and illustrations together.
            if provider != .openai, Keychain.loadKey(.openai) != nil {
                provider = .openai
            } else {
                UserDefaults.standard.set(provider.rawValue, forKey: "recalltutor_provider")
            }
        }
    }
    var availableProviders: [AIProvider] = []
    var hasAPIKey: Bool { !availableProviders.isEmpty }
    var hasOpenAIKey: Bool { Keychain.loadKey(.openai) != nil }

    /// Presents the Google sign-in sheet (required for the built-in tier).
    var showSignIn = false

    // Home screen topic chips, one pool per section
    var visibleTopics: [TopicCategory: [Topic]] = [:]
    /// True while the initial (or refresh) topic load is in-flight.
    /// HomeView shows shimmer placeholders instead of real chips.
    var isLoadingTopics = true
    // Categories whose "More" tap is generating fresh topics via the AI — the
    // button shows a spinner. Static-catalog refills are instant and never set this.
    var loadingMoreCategories: Set<TopicCategory> = []

    // Snapshot of the last failed exchange so the error banner can offer Retry.
    private var retrySnapshot: [ChatMessage]?
    var canRetry: Bool { retrySnapshot != nil }

    private var streamTask: Task<Void, Never>?
    /// Tracks the most recent topic-load task so pull-to-refresh (or a
    /// reading-level change) can cancel a stale in-flight generation.
    private var topicLoadTask: Task<Void, Never>?

    struct QuizSource {
        var question: String
        var cards: [String]
    }

    struct MasteryNote {
        var before: MasteryLevel
        var after: TopicMastery
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "recalltutor_reading_level")
        readingLevel = saved.flatMap(ReadingLevel.init(rawValue:)) ?? .high
        let savedProvider = UserDefaults.standard.string(forKey: "recalltutor_provider")
        provider = savedProvider.flatMap(AIProvider.init(rawValue:)) ?? .anthropic
        #if DEBUG
        // Simulator convenience: seed keys from the environment
        // (launch with SIMCTL_CHILD_ANTHROPIC_API_KEY=..., SIMCTL_CHILD_GEMINI_API_KEY=...,
        // or SIMCTL_CHILD_OPENAI_API_KEY=...).
        let env = ProcessInfo.processInfo.environment
        if Keychain.loadKey(.anthropic) == nil, let key = env["ANTHROPIC_API_KEY"], !key.isEmpty {
            Keychain.saveKey(key, account: .anthropic)
        }
        if Keychain.loadKey(.gemini) == nil, let key = env["GEMINI_API_KEY"], !key.isEmpty {
            Keychain.saveKey(key, account: .gemini)
        }
        if Keychain.loadKey(.openai) == nil, let key = env["OPENAI_API_KEY"], !key.isEmpty {
            Keychain.saveKey(key, account: .openai)
        }
        #endif
        refreshProviders()
        conversations = HistoryStore.load()
        // Show cached topics instantly (no shimmers), then silently refresh
        // in the background. If no cache exists, shimmers show as before.
        if let cached = TopicCache.load(for: readingLevel) {
            visibleTopics = cached
            isLoadingTopics = false
        }
        topicLoadTask = Task {
            await loadInitialTopics()
        }
        #if DEBUG
        // UI-testing hook: auto-open the most recent conversation.
        if ProcessInfo.processInfo.environment["RECALLTUTOR_AUTOSELECT"] != nil,
           let first = conversations.first {
            selectConversation(first)
        }
        #endif
    }

    var isEmpty: Bool { messages.isEmpty }

    /// Map of explored prompts → completion status, for the topic chips.
    var topicStatus: [String: TopicStatus] {
        var status: [String: TopicStatus] = [:]
        for conv in conversations {
            guard let firstUser = conv.messages.first(where: { $0.role == .user }) else { continue }
            let hasQuiz = !conv.quizzes.isEmpty
            let existing = status[firstUser.content]
            if existing == nil || (hasQuiz && existing == .partial) {
                status[firstUser.content] = hasQuiz ? .complete : .partial
            }
        }
        return status
    }

    // MARK: - Settings

    func saveKeys(anthropic: String, gemini: String, openai: String) {
        Keychain.saveKey(anthropic, account: .anthropic)
        Keychain.saveKey(gemini, account: .gemini)
        Keychain.saveKey(openai, account: .openai)
        refreshProviders()
    }

    /// Recompute which providers have keys. A supplied OpenAI key opts the
    /// entire tutor into OpenAI for text, realtime audio, and illustrations;
    /// without one, retain the existing Gemini/Firebase selection behavior.
    private func refreshProviders() {
        availableProviders = AIService.availableProviders()
        if Keychain.loadKey(.openai) != nil {
            provider = .openai
            return
        }
        if !availableProviders.contains(provider) {
            provider = availableProviders.contains(.anthropic) ? .anthropic : (availableProviders.first ?? .anthropic)
        }
        // A personal Gemini key always beats the metered Firebase tier —
        // never stay on Firebase once a key is available.
        if provider == .firebase, availableProviders.contains(.gemini) {
            provider = .gemini
        }
    }

    // MARK: - History persistence

    private func persist() {
        HistoryStore.save(conversations)
    }

    private func updateConversation(_ id: UUID, _ patch: (inout Conversation) -> Void) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        var conv = conversations[index]
        patch(&conv)
        conversations.remove(at: index)
        conversations.insert(conv, at: 0)
        persist()
    }

    // MARK: - Sending messages

    func sendMessage(_ content: String, fresh: Bool = false) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        let userMessage = ChatMessage(role: .user, content: trimmed)
        let newMessages = fresh ? [userMessage] : messages + [userMessage]
        messages = newMessages

        // Create or update the conversation record for this turn.
        var convId = fresh ? nil : activeId
        if convId == nil || !conversations.contains(where: { $0.id == convId }) {
            let id = UUID()
            convId = id
            activeId = id
            let now = Date()
            conversations.insert(
                Conversation(
                    id: id,
                    title: Conversation.title(forFirstMessage: trimmed),
                    messages: newMessages,
                    quizzes: [],
                    createdAt: now,
                    updatedAt: now
                ),
                at: 0
            )
            persist()
        } else if let convId {
            updateConversation(convId) {
                $0.messages = newMessages
                $0.updatedAt = Date()
            }
        }

        runExchange(newMessages, convId: convId!)
    }

    /// Stream one assistant reply for an already-recorded user turn. Kept
    /// separate from sendMessage so a failed exchange can be retried verbatim.
    private func runExchange(_ newMessages: [ChatMessage], convId: UUID) {
        // No provider at all (no API key and no Firebase config): show the
        // subscribe-or-enter-key screen instead of failing with an error.
        guard hasAPIKey else {
            rollBackDanglingTurn()
            SubscriptionManager.shared.showPaywall = true
            return
        }

        // The built-in (Firebase) tier is account-bound and metered: 3 free
        // lectures, then Pro. Continuing an already-counted lecture is free.
        if provider == .firebase {
            guard AuthManager.shared.isSignedIn else {
                rollBackDanglingTurn()
                showSignIn = true
                return
            }
            guard SubscriptionManager.shared.registerManagedLectureUse(lectureID: convId.uuidString) else {
                rollBackDanglingTurn()
                SubscriptionManager.shared.showPaywall = true
                return
            }
        }

        isStreaming = true
        showQuizButton = false
        errorMessage = nil
        retrySnapshot = nil

        messages = newMessages + [ChatMessage(role: .assistant, content: "")]

        streamTask = Task {
            var fullResponse = ""
            do {
                for try await text in AIService.streamChat(provider: provider, messages: newMessages, readingLevel: readingLevel) {
                    if Task.isCancelled { return }
                    fullResponse += text
                    messages = newMessages + [ChatMessage(role: .assistant, content: fullResponse)]
                }

                if !fullResponse.isEmpty {
                    let finalMessages = newMessages + [ChatMessage(role: .assistant, content: fullResponse)]
                    updateConversation(convId) {
                        $0.messages = finalMessages
                        $0.updatedAt = Date()
                    }
                }
                if fullResponse.count > 100 {
                    showQuizButton = true
                }
            } catch {
                if Task.isCancelled { return }
                messages = newMessages
                if case AnthropicError.missingAPIKey = error {
                    // Key was removed / never set: the paywall doubles as the
                    // "subscribe or enter your own key" screen (podchat-style).
                    rollBackDanglingTurn()
                    SubscriptionManager.shared.showPaywall = true
                } else if case OpenAIError.missingAPIKey = error {
                    // Key was removed / never set: the paywall doubles as the
                    // "subscribe or enter your own key" screen (podchat-style).
                    rollBackDanglingTurn()
                    SubscriptionManager.shared.showPaywall = true
                } else {
                    retrySnapshot = newMessages
                    errorMessage = error.localizedDescription
                }
            }
            isStreaming = false
        }
    }

    func retry() {
        guard let snapshot = retrySnapshot, !isStreaming, let activeId else { return }
        runExchange(snapshot, convId: activeId)
    }

    func dismissError() {
        errorMessage = nil
        retrySnapshot = nil
        // Without a reply there's nothing to show on the lecture screen —
        // return to the pre-send state instead of an empty page.
        rollBackDanglingTurn()
    }

    /// If the last turn is a user message that never got a reply (blocked by
    /// the paywall/sign-in gate or a failed request the user chose not to
    /// retry), drop it — otherwise the UI is left on an empty lecture screen.
    /// A fresh lecture rolls all the way back to the home screen and removes
    /// the conversation stub; a follow-up returns to the previous cards.
    private func rollBackDanglingTurn() {
        guard messages.last?.role == .user else { return }
        let prior = Array(messages.dropLast())
        messages = prior
        retrySnapshot = nil
        guard let convId = activeId else { return }
        if prior.isEmpty {
            conversations.removeAll { $0.id == convId }
            persist()
            activeId = nil
        } else if conversations.contains(where: { $0.id == convId }) {
            updateConversation(convId) {
                $0.messages = prior
                $0.updatedAt = Date()
            }
        }
    }

    // MARK: - Voice tutor

    /// Called by the lecture pager whenever cards or the visible card change.
    /// Creates and auto-connects the tutor on the first cards of a lecture
    /// (web parity: the overlay auto-connects on mount).
    func voiceTutorCardsChanged(all: [String], current: String?) {
        // Voice works with a Gemini or OpenAI key, or without a personal key
        // via the Firebase AI tier. Mirrors VoiceTutorManager.connect().
        let canUseVoice = Keychain.loadKey(.gemini) != nil
            || Keychain.loadKey(.openai) != nil
            || (FirebaseAIClient.isAvailable && AuthManager.shared.isSignedIn)
        guard canUseVoice else { return }
        let topic = messages.first(where: { $0.role == .user })?.content ?? ""
        guard !topic.isEmpty else { return }

        if voiceTutor == nil || voiceTutor?.topic != topic {
            voiceTutor?.disconnect()
            let tutor = VoiceTutorManager(topic: topic, readingLevel: readingLevel, provider: provider)
            voiceTutor = tutor
            tutor.connect()
        } else if voiceTutor?.status == .error {
            // A failed connect (network blip, quota) would otherwise leave the
            // tutor dead for the rest of the lecture — retry on the next card
            // event. Card flips are user-paced, so this can't storm the API.
            voiceTutor?.connect()
        }
        voiceTutor?.updateCards(all: all, current: current)
    }

    private func tearDownVoiceTutor() {
        voiceTutor?.disconnect()
        voiceTutor = nil
    }

    // MARK: - Navigation

    func newChat() {
        // Cancel any in-flight lecture stream so its chunk updates can't
        // re-populate the messages we're about to clear.
        streamTask?.cancel()
        streamTask = nil
        tearDownVoiceTutor()
        quizSource = nil
        masteryNote = nil
        messages = []
        activeId = nil
        showQuizButton = false
        isStreaming = false
        errorMessage = nil
        retrySnapshot = nil
    }

    func selectConversation(_ conversation: Conversation) {
        guard !isStreaming else { return }
        tearDownVoiceTutor()
        messages = conversation.messages
        activeId = conversation.id
        let last = conversation.messages.last
        showQuizButton = last?.role == .assistant && (last?.content.count ?? 0) > 100
        errorMessage = nil
    }

    func deleteConversation(_ id: UUID) {
        guard !isStreaming else { return }
        conversations.removeAll { $0.id == id }
        persist()
        if id == activeId {
            newChat()
        }
    }

    /// Replace every category's chips with fresh topics (pull-to-refresh).
    func refreshAllTopics() async {
        topicLoadTask?.cancel()
        visibleTopics = [:]
        isLoadingTopics = true
        await loadInitialTopics()
    }

    /// Load topics: try AI generation first; fall back to the static catalog
    /// if there's no API key or every request fails (including cancellation).
    ///
    /// When cached topics are already visible (populated in `init`), we skip
    /// the shimmer state and silently swap in fresh AI results.
    func loadInitialTopics() async {
        let hasCachedTopics = !visibleTopics.isEmpty
        // Only show shimmers if nothing is on screen yet.
        if !hasCachedTopics {
            isLoadingTopics = true
        }
        defer { isLoadingTopics = false }

        if hasAPIKey {
            let currentProvider = provider
            let level = readingLevel
            var aiResults: [TopicCategory: [Topic]] = [:]

            await withTaskGroup(of: (TopicCategory, [Topic]?).self) { group in
                for category in TopicCategory.allCases {
                    group.addTask {
                        // Cancelled tasks throw CancellationError; try? turns
                        // that into nil, so aiResults stays empty → fallback.
                        (category, try? await AIService.generateTopics(
                            provider: currentProvider,
                            category: category.rawValue,
                            readingLevel: level,
                            excluding: []
                        ))
                    }
                }
                for await (category, generated) in group {
                    if let generated {
                        aiResults[category] = generated
                    }
                }
            }

            if !aiResults.isEmpty {
                // Fill any categories the AI missed with static picks.
                for category in TopicCategory.allCases where aiResults[category] == nil {
                    aiResults[category] = TopicCatalog.pickTopics(
                        category: category, level: level
                    )
                }
                visibleTopics = aiResults
                TopicCache.save(aiResults, level: level)
                return
            }
        }

        // Fallback: no API key, all AI requests failed, or task cancelled.
        var fallback: [TopicCategory: [Topic]] = [:]
        for category in TopicCategory.allCases {
            fallback[category] = TopicCatalog.pickTopics(
                category: category, level: readingLevel
            )
        }
        visibleTopics = fallback
    }

    func loadMoreTopics(for category: TopicCategory) {
        guard !loadingMoreCategories.contains(category) else { return }
        let existing = Set((visibleTopics[category] ?? []).map(\.prompt))
        if hasAPIKey {
            loadingMoreCategories.insert(category)
            Task {
                if let generated = try? await AIService.generateTopics(
                    provider: provider,
                    category: category.rawValue,
                    readingLevel: readingLevel,
                    excluding: existing
                ) {
                    visibleTopics[category, default: []] += generated
                } else {
                    visibleTopics[category, default: []] += TopicCatalog.pickTopics(
                        category: category, level: readingLevel, excluding: existing
                    )
                }
                loadingMoreCategories.remove(category)
            }
        } else {
            visibleTopics[category, default: []] += TopicCatalog.pickTopics(
                category: category, level: readingLevel, excluding: existing
            )
        }
    }

    // MARK: - Quiz

    /// Launch a quiz grounded in the lecture cards of the latest answer.
    func startQuiz() {
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else { return }
        let lastUser = messages.last(where: { $0.role == .user })
        quizSource = QuizSource(
            question: lastUser?.content ?? "",
            cards: CardSplitter.splitIntoCards(lastAssistant.content)
        )
        masteryNote = nil
        showQuizButton = false
    }

    func recordQuizCompletion(score: Int, total: Int) {
        guard let activeId, let existing = conversations.first(where: { $0.id == activeId }) else { return }
        let record = QuizRecord(score: score, total: total, takenAt: Date())
        updateConversation(activeId) {
            $0.quizzes.append(record)
            $0.updatedAt = Date()
        }
        // Snapshot mastery before/after this quiz so the scorecard can show
        // topic development (and celebrate level-ups).
        var updated = existing
        updated.quizzes.append(record)
        masteryNote = MasteryNote(
            before: Mastery.compute(for: existing).level,
            after: Mastery.compute(for: updated)
        )
    }

    /// "Return to home" from the scorecard.
    func closeQuizToHome() {
        tearDownVoiceTutor()
        quizSource = nil
        messages = []
        activeId = nil
        showQuizButton = false
        errorMessage = nil
    }

    /// Dismiss (X) — back to the lecture with the quiz button restored.
    func dismissQuiz() {
        quizSource = nil
        showQuizButton = true
        errorMessage = nil
        voiceTutor?.quizStateChanged(isActive: false)
    }

    /// "Go deeper" — continue the conversation diving further into the topic.
    func goDeeper() {
        let topic = quizSource?.question ?? "the previous topic"
        // Carry over the existing messages so the AI knows what was already
        // covered and can dive deeper rather than repeating the same content.
        let previousMessages = messages
        // The deep dive is a new lecture — the voice tutor must be rebuilt
        // around the new topic and cards, not the old set.
        tearDownVoiceTutor()
        quizSource = nil
        errorMessage = nil

        let prompt = "Now go deeper on this topic. Cover advanced concepts, subtleties, edge cases, and related ideas that you haven't covered yet. Don't repeat what you already explained — build on it."
        let userMessage = ChatMessage(role: .user, content: prompt)
        messages = previousMessages + [userMessage]

        if let convId = activeId {
            updateConversation(convId) {
                $0.messages = previousMessages + [userMessage]
                $0.updatedAt = Date()
            }
            runExchange(previousMessages + [userMessage], convId: convId)
        } else {
            sendMessage(
                "Go deeper on the topic: \"\(topic)\". Please explain the advanced concepts, subtleties, and edge cases in more detail.",
                fresh: true
            )
        }
    }
}
