import CoreText
import SwiftUI

/// Colors and type agreed in Notion 02 §6-3 (Rhyme-like palette, Zen Kaku Gothic New + Plus Jakarta Sans).
enum Theme {
    static let ink = Color(hex: 0x1E1E1E)
    static let surface = Color(hex: 0xFEFEFE)
    static let base = Color(hex: 0xF4F4F4)
    static let fill = Color(hex: 0xEFEFEF)
    static let rangeFill = Color(hex: 0xE6E6E6)
    static let line = Color(hex: 0xDCDCDC)
    static let secondary = Color(hex: 0x8A8A8A)
    static let faint = Color(hex: 0xC8C8C8)

    /// Japanese text.
    static func jp(_ size: CGFloat, _ weight: JPWeight = .regular) -> Font {
        .custom(weight.postScriptName, size: size)
    }

    /// Latin text and numbers.
    static func latin(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Plus Jakarta Sans", size: size).weight(weight)
    }

    enum JPWeight {
        case regular, medium, bold

        var postScriptName: String {
            switch self {
            case .regular: "ZenKakuGothicNew-Regular"
            case .medium: "ZenKakuGothicNew-Medium"
            case .bold: "ZenKakuGothicNew-Bold"
            }
        }
    }

    /// Registers the bundled fonts once at launch (no Info.plist entry needed).
    static func registerFonts() {
        let names = ["ZenKakuGothicNew-Regular", "ZenKakuGothicNew-Medium", "ZenKakuGothicNew-Bold", "PlusJakartaSans"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
