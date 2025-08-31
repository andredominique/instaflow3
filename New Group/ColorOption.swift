//
//  ColorOption.swift
//  InstaFlow
//
//  Extracted from SelectionsView without any functional changes.
//

import SwiftUI

/// Color choices for background/border quick-pick.
/// NOTE: previously declared `private` inside SelectionsView; moved out unchanged in behavior.
enum ColorOption: CaseIterable {
    case white, black, custom
    
    var color: Color {
        switch self {
        case .white: return .white
        case .black: return .black
        case .custom: return .black // default; overridden by color picker
        }
    }
    
    var title: String {
        switch self {
        case .white: return "White"
        case .black: return "Black"
        case .custom: return "Custom"
        }
    }
}
