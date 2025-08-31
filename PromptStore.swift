
import Foundation

struct PromptPreset: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var text: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

@MainActor
final class PromptStore: ObservableObject {
    static let shared = PromptStore()
    @Published var presets: [PromptPreset] = []

    private init() { loadAll() }

    private var fileURL: URL {
        let appSup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSup.appendingPathComponent("InstaFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("presets.json")
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(presets)
            try data.write(to: fileURL, options: .atomic)
        } catch { print("Preset save error: \(error)") }
    }

    private func loadAll() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let arr = try? JSONDecoder().decode([PromptPreset].self, from: data) {
            presets = arr
        }
    }

    func add(title: String, text: String) {
        presets.append(.init(title: title, text: text))
        save()
    }

    func delete(_ p: PromptPreset) {
        presets.removeAll { $0.id == p.id }
        save()
    }

    func rename(_ p: PromptPreset, to newTitle: String) {
        if let idx = presets.firstIndex(of: p) {
            presets[idx].title = newTitle
            presets[idx].updatedAt = Date()
            save()
        }
    }

    func updateText(_ p: PromptPreset, to newText: String) {
        if let idx = presets.firstIndex(of: p) {
            presets[idx].text = newText
            presets[idx].updatedAt = Date()
            save()
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        presets.move(fromOffsets: source, toOffset: destination)
        save()
    }
}
