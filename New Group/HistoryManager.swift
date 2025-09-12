import Foundation
import Combine

final class HistoryManager: ObservableObject {
    @Published private var stack: [[ProjectImage]] = []
    private var index: Int = -1

    var canUndo: Bool { index > 0 }
    var canRedo: Bool { index >= 0 && index < stack.count - 1 }
    var isEmpty: Bool { stack.isEmpty }

    // Save a new snapshot (truncates redo branch)
    func save(_ images: [ProjectImage]) {
        if index < stack.count - 1 {
            stack = Array(stack.prefix(index + 1))
        }
        stack.append(images)
        index = stack.count - 1
        objectWillChange.send()
    }

    func undo() -> [ProjectImage]? {
        guard canUndo else { return nil }
        index -= 1
        objectWillChange.send()
        return stack[index]
    }

    func redo() -> [ProjectImage]? {
        guard canRedo else { return nil }
        index += 1
        objectWillChange.send()
        return stack[index]
    }
}

