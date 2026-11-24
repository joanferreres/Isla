import SwiftUI
import IslandCore

enum RecordPlayerPalette: String, CaseIterable, Identifiable {
    case noir, blue, amber, emerald, lilac, ruby, silver, turquoise, copper, lime

    var id: Self { self }

    private var style: (title: String, shortcut: String, background: UInt32, accent: UInt32, ink: UInt32, vinyl: UInt32, metal: UInt32) {
        switch self {
        case .noir:    ("Noir",      "0", 0x101012, 0xF6F4EF, 0xFCFBF8, 0x1C1C1F, 0x929399)
        case .blue:    ("Azul",      "1", 0x0B1017, 0x7AB0FF, 0xEBF2FF, 0x0E1117, 0xA1B8D6)
        case .amber:   ("Ámbar",     "2", 0x170F0B, 0xFAB563, 0xFFF0DB, 0x1A110D, 0xC7A87D)
        case .emerald: ("Esmeralda", "3", 0x0B1915, 0x72E2B3, 0xE1FFF2, 0x10231E, 0x90C2AB)
        case .lilac:   ("Lavanda",   "4", 0x171021, 0xC4ACFF, 0xF4EBFF, 0x1E172B, 0xBBAACE)
        case .ruby:    ("Rubí",      "5", 0x1E0D15, 0xFF8EA9, 0xFFEDF1, 0x2C1420, 0xD5A2AE)
        case .silver:  ("Plata",     "6", 0x141619, 0xD9E1EE, 0xF1F4F8, 0x22252A, 0xBDC6D3)
        case .turquoise: ("Turquesa", "7", 0x071A22, 0x59DBF0, 0xE1FBFF, 0x0C2730, 0x8BBBC5)
        case .copper:  ("Cobre",     "8", 0x21130E, 0xE99273, 0xFFF0E6, 0x302018, 0xBC937D)
        case .lime:    ("Lima",      "9", 0x171A0C, 0xD0EE69, 0xF7FFE1, 0x232813, 0xA6B87B)
        }
    }

    var title: String { style.title }
    var shortcut: String { style.shortcut }
    var background: NSColor { color(style.background) }
    var accent: Color { Color(nsColor: color(style.accent)) }
    var ink: Color { Color(nsColor: color(style.ink)) }
    var vinyl: Color { Color(nsColor: color(style.vinyl)) }
    var metal: Color { Color(nsColor: color(style.metal)) }

    private func color(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed: Double((rgb >> 16) & 0xFF) / 255,
                green: Double((rgb >> 8) & 0xFF) / 255,
                blue: Double(rgb & 0xFF) / 255, alpha: 1)
    }
}
