import Foundation

/// A small, persisted representation of the user's preferred UI language.
///
/// Design notes:
/// - We store this enum in `UserDefaults` (via SwiftUI's `@AppStorage`) as a `String`.
/// - Therefore, the `rawValue` strings are part of the app's *storage contract*.
///   Changing them would break existing user preferences.
/// - We intentionally keep the type independent from SwiftUI so it can be used from
///   both UI and non-UI layers (services, tests, etc.).
enum AppLanguage: String, CaseIterable, Codable {
    /// Follow the system language (no explicit override).
    case system = "system"

    /// Force English UI.
    case english = "en"

    /// Force Simplified Chinese UI.
    ///
    /// "zh-Hans" is the standard language tag for Simplified Chinese (Hans = Simplified script).
    case simplifiedChinese = "zh-Hans"

    /// A short, user-facing label suitable for a SwiftUI `Picker`.
    ///
    /// We keep these strings in one place to avoid duplicating literals across Views.
    /// When the app becomes fully localized, this can be migrated to `Localizable.strings`.
    var pickerTitle: String {
        switch self {
        case .system:
            return "System Default"
        case .english:
            return "English"
        case .simplifiedChinese:
            return "中文"
        }
    }

    /// Safe initializer when reading from persistent storage.
    ///
    /// In the real world, stored values can be missing, empty, from an older app version,
    /// or manually edited by advanced users. Instead of crashing or producing `nil`, we
    /// defensively fall back to `.system`.
    init(storedRawValue: String?) {
        guard let storedRawValue, !storedRawValue.isEmpty else {
            self = .system
            return
        }
        self = AppLanguage(rawValue: storedRawValue) ?? .system
    }

    func shouldTranslateSkillContent(locale: Locale) -> Bool {
        switch self {
        case .english:
            return true
        case .simplifiedChinese:
            return true
        case .system:
            return locale.language.languageCode?.identifier == "en"
        }
    }
}
