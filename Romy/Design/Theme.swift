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
    /// The blue of the buttons that guide (Rhyme's 案内ボタン, about #2FA8F5): the route button of a move.
    static let guide = Color(hex: 0x2FA8F5)
    /// 「元に戻す」 on the dark note.
    static let undo = Color(hex: 0xFE9000)

    /// One color per day, the same on tabs, cards and (later) map pins (Notion 02 §6-3, §6-5).
    /// The first three are agreed; the rest are added so longer trips still get a color.
    private static let dayColors: [Color] = [
        Color(hex: 0x0097FF), Color(hex: 0xFF4200), Color(hex: 0xFE9000),
        Color(hex: 0x00B37E), Color(hex: 0x8E5CF6), Color(hex: 0xE5338B), Color(hex: 0x00A3A3)
    ]

    /// Color of a day; 未定 (nil) is grey.
    static func dayColor(_ day: Int?) -> Color {
        guard let day, day >= 1 else { return secondary }
        return dayColors[(day - 1) % dayColors.count]
    }

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
