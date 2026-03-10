import AppKit
import SwiftUI

enum FontSettings {
    static let familyKey = "uiFontFamily"
    static let sizeKey = "uiFontSize"
    static let systemFontFamily = "System"
    static let defaultFontSize: Double = 13
    static let minFontSize: Double = 11
    static let maxFontSize: Double = 24

    static var availableFontFamilies: [String] {
        let families = NSFontManager.shared.availableFontFamilies
        let sortedFamilies = families.sorted()
        return [systemFontFamily] + sortedFamilies.filter { $0 != systemFontFamily }
    }

    static func font(family: String, size: Double) -> Font {
        let normalizedSize = min(max(size, minFontSize), maxFontSize)
        if family == systemFontFamily {
            return .system(size: normalizedSize)
        }
        return .custom(family, size: normalizedSize)
    }

    /// Convert a text style into a scaled point size based on the user's base size.
    /// This keeps relative typography (title, caption, etc.) while honoring the chosen base size.
    static func scaledSize(baseSize: Double, textStyle: Font.TextStyle) -> Double {
        let clampedBaseSize = min(max(baseSize, minFontSize), maxFontSize)
        let preferredBodySize = NSFont.preferredFont(forTextStyle: .body).pointSize
        let preferredStyleSize = NSFont.preferredFont(forTextStyle: nsTextStyle(for: textStyle)).pointSize
        let scale = preferredStyleSize / max(preferredBodySize, 1)
        return clampedBaseSize * scale
    }

    /// Create a SwiftUI Font for a text style, with optional design (e.g., monospaced).
    static func font(family: String, baseSize: Double, textStyle: Font.TextStyle, design: Font.Design? = nil) -> Font {
        let size = scaledSize(baseSize: baseSize, textStyle: textStyle)
        if family == systemFontFamily {
            return .system(size: size, design: design ?? .default)
        }
        if design == .monospaced {
            return .system(size: size, design: .monospaced)
        }
        return .custom(family, size: size)
    }

    /// Bridge SwiftUI's TextStyle to AppKit's NSFont.TextStyle for size lookup.
    private static func nsTextStyle(for textStyle: Font.TextStyle) -> NSFont.TextStyle {
        switch textStyle {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .caption: return .caption1
        case .caption2: return .caption2
        case .footnote: return .footnote
        @unknown default:
            return .body
        }
    }
}
