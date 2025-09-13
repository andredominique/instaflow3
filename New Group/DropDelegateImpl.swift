import SwiftUI
import AppKit

struct DropDelegateImpl: DropDelegate {
    let overItem: ProjectImage
    @Binding var allItems: [ProjectImage]
    @Binding var draggingID: UUID?
    let isShiftPressed: Bool
    let isCommandPressed: Bool
    let saveToHistory: () -> Void  // NEW: Add history saving callback
    @ObservedObject var model: AppModel

    func dropEntered(info: DropInfo) {
        // Only allow reordering when NOT in modifier key mode
        guard !(isShiftPressed || isCommandPressed) else { return }
        
        guard
            let draggingID = draggingID,
            draggingID != overItem.id,
            let from = allItems.firstIndex(where: { $0.id == draggingID }),
            let to   = allItems.firstIndex(where: { $0.id == overItem.id })
        else { return }

        // NEW: Save history before making changes
        saveToHistory()

        withAnimation(.easeInOut(duration: 0.12)) {
            let moving = allItems.remove(at: from)
            allItems.insert(moving, at: to)
            for i in allItems.indices { allItems[i].orderIndex = i }
            model.project.hasCustomOrder = true // Mark that we have a custom order
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        if !(isShiftPressed || isCommandPressed) {
            draggingID = nil
        }
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Disable drop operations when in modifier key mode
        guard !(isShiftPressed || isCommandPressed) else { return DropProposal(operation: .forbidden) }
        return DropProposal(operation: .move)
    }
}