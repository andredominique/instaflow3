import Foundation
import SwiftUI

// MARK: - Aspect Presets
enum AspectPreset: String, Codable, CaseIterable, Identifiable {
    case square1x1
    case feed4x5
    case story9x16

    var id: String { rawValue }
    var title: String {
        switch self {
        case .square1x1: return "1:1"
        case .feed4x5:  return "4:5"
        case .story9x16: return "9:16"
        }
    }
    var aspect: CGFloat {
        switch self {
        case .square1x1: return 1.0
        case .feed4x5:  return 4.0 / 5.0
        case .story9x16: return 9.0 / 16.0
        }
    }
}

// MARK: - Codable sRGB Color
struct ColorData: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double = 1.0

    static let white = ColorData(red: 1, green: 1, blue: 1, opacity: 1)
    static let black = ColorData(red: 0, green: 0, blue: 0, opacity: 1)

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue).opacity(opacity)
    }
}

// MARK: - Project Image
struct ProjectImage: Identifiable, Codable {
    let id: UUID
    var url: URL
    var orderIndex: Int
    var disabled: Bool

    // Repositioning offset (normalized)
    var offsetX: Double = 0.0
    var offsetY: Double = 0.0

    init(id: UUID = UUID(), url: URL, orderIndex: Int, disabled: Bool = false) {
        self.id = id
        self.url = url
        self.orderIndex = orderIndex
        self.disabled = disabled
    }
}

// MARK: - Project
struct Project: Identifiable, Codable {
    let id: UUID

    // Basic
    var name: String
    var caption: String
    var images: [ProjectImage]

    // Aspect & crop
    var aspect: AspectPreset = .story9x16
    var cropEnabled: Bool = true
    var zoomToFill: Bool = true

    // (Legacy/other) settings
    var carouselBorderPx: Int = 0
    var carouselBorderColor: ColorData = .black
    var reelBorderPx: Int = 0
    var reelBorderColor: ColorData = .black
    var reelSecondsPerImage: Double = 2.0

    // Export/misc
    var saveCaptionTxt: Bool = true
    var referenceName: String = ""
    var outputPath: URL? = nil

    // Folder picker support
    var watchPath: URL? = nil
    var selectedFolders: [URL] = []

    // ================================
    // Selection Visual Settings (persistent)
    // ================================
    var selectionBorderWidth: Double = 0
    var selectionBackgroundHex: String = "#000000"
    var selectionColorOption: String = "black" // "white" | "black" | "custom"
    var hasCustomOrder: Bool = false // Track if images have been manually reordered

    var selectionBackgroundColor: Color {
        get { Color(hex: selectionBackgroundHex) ?? .black }
        set { selectionBackgroundHex = newValue.hexString() ?? "#000000" }
    }

    init(id: UUID = UUID(),
         name: String = "",
         caption: String = "",
         images: [ProjectImage] = []) {
        self.id = id
        self.name = name
        self.caption = caption
        self.images = images
    }
}

// MARK: - Color ↔ Hex helpers (macOS)
#if os(macOS)
import AppKit

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let v = UInt64(s, radix: 16), s.count == 6 else { return nil }
        let r = Double((v & 0xFF0000) >> 16) / 255.0
        let g = Double((v & 0x00FF00) >> 8) / 255.0
        let b = Double(v & 0x0000FF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }

    func hexString() -> String? {
        let ns = NSColor(self)
        guard let rgb = ns.usingColorSpace(.deviceRGB) else { return nil }
        let r = Int((rgb.redComponent   * 255.0).rounded())
        let g = Int((rgb.greenComponent * 255.0).rounded())
        let b = Int((rgb.blueComponent  * 255.0).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
#endif
