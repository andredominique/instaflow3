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
        // Don't save if the state is exactly the same as the last one
        if !stack.isEmpty, areImagesEqual(stack[index], images) {
            return
        }
        
        // Truncate any redo history
        if index < stack.count - 1 {
            stack = Array(stack.prefix(index + 1))
        }
        
        // Create a deep copy of the images to preserve state
        let imageCopy = images.map { image in
            var copy = image
            copy.offsetX = image.offsetX
            copy.offsetY = image.offsetY
            return copy
        }
        
        stack.append(imageCopy)
        index = stack.count - 1
        objectWillChange.send()
    }
    
    // Helper to compare two arrays of ProjectImage
    private func areImagesEqual(_ a: [ProjectImage], _ b: [ProjectImage]) -> Bool {
        guard a.count == b.count else { return false }
        
        for (img1, img2) in zip(a, b) {
            if img1.id != img2.id ||
               img1.offsetX != img2.offsetX ||
               img1.offsetY != img2.offsetY ||
               img1.disabled != img2.disabled ||
               img1.url != img2.url {
                return false
            }
        }
        return true
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

