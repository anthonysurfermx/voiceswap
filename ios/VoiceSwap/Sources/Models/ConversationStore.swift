import Foundation

@MainActor
class ConversationStore: ObservableObject {

    @Published private(set) var conversations: [Conversation] = []

    private let directory: URL

    static let shared = ConversationStore()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        directory = docs.appendingPathComponent("conversations", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadAll()
    }

    // MARK: - CRUD

    @discardableResult
    func create(title: String = "New Conversation") -> Conversation {
        let conv = Conversation(title: title)
        conversations.insert(conv, at: 0)
        save(conv)
        return conv
    }

    func appendMessage(to conversationId: UUID, message: TranscriptMessage) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].messages.append(message)
        conversations[idx].updatedAt = Date()

        // Auto-title from first user message
        if conversations[idx].title == "New Conversation",
           message.role == "user", !message.text.isEmpty {
            conversations[idx].title = String(message.text.prefix(50))
        }

        save(conversations[idx])

        // Move to top (most recent)
        if idx != 0 {
            let conv = conversations.remove(at: idx)
            conversations.insert(conv, at: 0)
        }
    }

    func updateTitle(conversationId: UUID, title: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].title = title
        save(conversations[idx])
    }

    func delete(conversationId: UUID) {
        conversations.removeAll { $0.id == conversationId }
        let file = directory.appendingPathComponent("\(conversationId).json")
        try? FileManager.default.removeItem(at: file)
    }

    // MARK: - Persistence

    private func save(_ conversation: Conversation) {
        let file = directory.appendingPathComponent("\(conversation.id).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(conversation) {
            try? data.write(to: file, options: .atomic)
        }
    }

    private func loadAll() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }) else { return }

        var loaded: [Conversation] = []
        for file in files {
            if let data = try? Data(contentsOf: file),
               let conv = try? decoder.decode(Conversation.self, from: data) {
                loaded.append(conv)
            }
        }
        conversations = loaded.sorted { $0.updatedAt > $1.updatedAt }
    }
}
