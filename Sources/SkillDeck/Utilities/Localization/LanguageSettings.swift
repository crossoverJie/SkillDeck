import Foundation

/// A namespace for language-related user preference keys and defaults.
///
/// We follow the existing pattern in `FontSettings`: keep `UserDefaults` keys as `static let`
/// constants in one place, so `@AppStorage` / `UserDefaults` access is typo-proof and consistent.
enum LanguageSettings {
    /// UserDefaults key for the user's chosen app language override.
    ///
    /// Prefixing with `ui` matches the existing UI preference keys (`uiFontFamily`, `uiFontSize`).
    static let appLanguageKey = "uiAppLanguage"

    /// Default preference when the user has not chosen a language.
    static let defaultLanguage: AppLanguage = .system

    /// Resolve the bundle/locale selected by the persisted app-language preference.
    ///
    /// `LocalizedError.errorDescription` has no access to the SwiftUI environment,
    /// so service-layer errors resolve the user's preference here.
    static func currentResolution(defaults: UserDefaults = .standard) -> LocalizationResolver.Resolution {
        let language = AppLanguage(storedRawValue: defaults.string(forKey: appLanguageKey))
        return LocalizationResolver.resolve(language: language)
    }
}
