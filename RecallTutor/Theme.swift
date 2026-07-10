import SwiftUI

// Cool slate-and-blue palette (Tailwind slate neutrals, blue accent).
enum Theme {
    static let page = Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255)   // slate-50
    static let surface = Color.white
    static let userBubble = Color(red: 226 / 255, green: 232 / 255, blue: 240 / 255) // slate-200
    static let textPrimary = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255)   // slate-900
    static let textSecondary = Color(red: 51 / 255, green: 65 / 255, blue: 85 / 255) // slate-700
    static let textTertiary = Color(red: 71 / 255, green: 85 / 255, blue: 105 / 255)   // slate-600
    static let accent = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)      // blue-500
    static let accentStrong = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255) // blue-600
    static let danger = Color(red: 153 / 255, green: 27 / 255, blue: 27 / 255)
    static let borderSubtle = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).opacity(0.15)
    static let borderSoft = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).opacity(0.08)
    static let stateHover = textTertiary.opacity(0.08)
    static let statePill = textTertiary.opacity(0.10)

    // Quiz reveal tones (Tailwind emerald/rose/amber equivalents).
    static let correctBorder = Color(red: 0.020, green: 0.588, blue: 0.412)  // emerald-600
    static let correctFill = Color(red: 0.925, green: 0.992, blue: 0.961)    // emerald-50
    static let correctText = Color(red: 0.024, green: 0.373, blue: 0.275)    // emerald-800
    static let wrongBorder = Color(red: 0.882, green: 0.114, blue: 0.282)    // rose-600
    static let wrongFill = Color(red: 1.0, green: 0.945, blue: 0.949)        // rose-50
    static let wrongText = Color(red: 0.622, green: 0.043, blue: 0.176)      // rose-800
    static let amberFill = Color(red: 0.996, green: 0.953, blue: 0.780)      // amber-100
    static let amberText = Color(red: 0.573, green: 0.251, blue: 0.055)      // amber-800
    static let amberBar = Color(red: 0.961, green: 0.620, blue: 0.043)       // amber-500
    static let emeraldFill = Color(red: 0.820, green: 0.980, blue: 0.898)    // emerald-100
    static let emeraldBar = Color(red: 0.063, green: 0.725, blue: 0.506)     // emerald-500
    static let roseFill = Color(red: 1.0, green: 0.894, blue: 0.902)         // rose-100
}

extension Font {
    /// Titles: Libre Baskerville (bundled, registered at launch). The
    /// variable font spans wght 400–700, so heavier requests map to Bold.
    static func serifDisplay(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .semibold, .bold, .heavy, .black:
            .custom("LibreBaskerville-Bold", size: size)
        default:
            .custom("LibreBaskerville-Regular", size: size)
        }
    }

    /// Everything else: Baskervville (variable wght 400–700), with the
    /// requested weight applied on top of the variable axis.
    static func appBody(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Baskervville-Regular", size: size).weight(weight)
    }
}
