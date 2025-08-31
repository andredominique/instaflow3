import Foundation

// MARK: - Single source of truth for chat models

public struct ChatMessage: Identifiable, Hashable, Codable {
    public var id: UUID = UUID()
    public var role: String            // "user" | "assistant" | "system"
    public var content: String
    public var createdAt: Date = Date()
}

public struct ChatSession: Identifiable, Hashable, Codable {
    public var id: UUID = UUID()
    public var title: String
    public var messages: [ChatMessage] = []
    public var updatedAt: Date = Date()
}
