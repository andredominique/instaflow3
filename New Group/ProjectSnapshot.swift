//
//  ProjectSnapshot.swift
//  InstaFlow
//
//  Extracted helper used by HistoryManager.
//

import Foundation

/// Snapshot of project images used for undo/redo.
/// NOTE: previously `private struct` inside SelectionsView; moved to file-scope.
struct ProjectSnapshot {
    let images: [ProjectImage]
    let timestamp: Date
}
