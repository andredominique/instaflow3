import Foundation

final class ChatStore: ObservableObject {
    static let shared = ChatStore()

    @Published var sessions: [ChatSession] = []
    @Published var current: ChatSession? {
        didSet { save() }
    }

    private let saveURL: URL

    private init() {
        // Build ~/Library/Application Support/InstaFlow/Chats.json
        let fm = FileManager.default
        let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = (appSupport ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent("InstaFlow", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.saveURL = dir.appendingPathComponent("Chats.json")

        load()
        if current == nil, let first = sessions.first { current = first }
    }

    // MARK: - Session ops

    @discardableResult
    func newSession(title: String) -> ChatSession {
        let s = ChatSession(id: UUID(), title: title, messages: [], updatedAt: Date())
        sessions.insert(s, at: 0)
        current = s
        save()
        return s
    }

    func duplicate(_ session: ChatSession) {
        var copy = session
        copy.id = UUID()
        copy.title = session.title + " (copy)"
        copy.updatedAt = Date()
        sessions.insert(copy, at: 0)
        current = copy
        save()
    }

    func delete(_ session: ChatSession) {
        sessions.removeAll { $0.id == session.id }
        if current?.id == session.id {
            current = sessions.first
        }
        save()
    }

    func append(role: String, content: String) {
        guard var cur = current else { return }
        cur.messages.append(ChatMessage(role: role, content: content))
        cur.updatedAt = Date()
        replace(cur)
    }

    func replace(_ session: ChatSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        }
        if current?.id == session.id {
            current = session
        }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        if let decoded = try? JSONDecoder().decode([ChatSession].self, from: data) {
            self.sessions = decoded
            // Choose most recent as current
            self.current = decoded.sorted(by: { $0.updatedAt > $1.updatedAt }).first
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(sessions) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }
}
