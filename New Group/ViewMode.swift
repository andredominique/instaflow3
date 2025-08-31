import SwiftUI
import AppKit

enum ViewMode: CaseIterable {
    case full
    case crop9x16
    case crop4x5
    
    var title: String {
        switch self {
        case .full: return "Full"
        case .crop9x16: return "9:16"
        case .crop4x5: return "4:5"
        }
    }
    
    var aspectRatio: CGFloat? {
        switch self {
        case .full: return nil
        case .crop9x16: return 9.0/16.0
        case .crop4x5: return 4.0/5.0
        }
    }
}