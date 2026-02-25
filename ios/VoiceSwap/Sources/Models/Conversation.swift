import Foundation

struct TranscriptMessage: Codable, Identifiable {
    let id: UUID
    let role: String          // "user" or "assistant"
    let text: String
    let timestamp: Date
    let source: String?       // "voice" (Gemini), "text" (typed), "system"

    init(role: String, text: String, source: String? = nil) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.timestamp = Date()
        self.source = source
    }
}

struct Conversation: Codable, Identifiable {
    let id: UUID
    var title: String
    var subtitle: String?
    var messages: [TranscriptMessage]
    let createdAt: Date
    var updatedAt: Date

    init(title: String = "New Conversation") {
        self.id = UUID()
        self.title = title
        self.subtitle = nil
        self.messages = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var lastMessageText: String? {
        messages.last?.text
    }

    var lastMessageDate: Date? {
        messages.last?.timestamp
    }
}
