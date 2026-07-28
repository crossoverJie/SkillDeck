import Foundation

/// Resolves the concrete `Locale` and `Bundle` used for localization.
///
/// This is intentionally a small, pure utility (no SwiftUI, no global state) so it is easy to
/// unit test and safe to use from both UI and service layers.
enum LocalizationResolver {

    /// A simple output model representing the runtime localization context.
    ///
    /// We return a struct (instead of a tuple) so call sites are self-documenting and extensible.
    struct Resolution {
        /// The `Locale` that should be used to format and display locale-sensitive values.
        let locale: Locale

        /// The `Bundle` to use when looking up localized strings and resources.
        let bundle: Bundle
    }

    /// Decide which `Locale` and `Bundle` to use for a given `AppLanguage`.
    ///
    /// Behavior contract (per Task 2):
    /// - `.system`:
    ///   - `locale` is `Locale.autoupdatingCurrent` (follows system changes live)
    ///   - `bundle` is the provided `baseBundle`
    /// - explicit language (e.g. `en`, `zh-Hans`):
    ///   - `locale` is `Locale(identifier: rawValue)` (deterministic override)
    ///   - `bundle` remains `baseBundle`; `L10n.string` selects the matching `.lproj` inside it
    ///
    /// - Parameters:
    ///   - language: User preference.
    ///   - baseBundle: Bundle that contains localization resources. Defaults to `Bundle.module`
    ///     via `SkillDeckResources.bundle`.
    static func resolve(
        language: AppLanguage,
        baseBundle: Bundle = SkillDeckResources.bundle
    ) -> Resolution {
        switch language {
        case .system:
            // `autoupdatingCurrent` is important on macOS because the user can change system
            // language/region while the app is running. Using the non-autoupdating `current`
            // would require re-launching to reflect those changes.
            return Resolution(locale: .autoupdatingCurrent, bundle: baseBundle)

        case .english, .simplifiedChinese:
            // Create a deterministic locale override.
            let locale = Locale(identifier: language.rawValue)
            // Keep the resource-root bundle in the SwiftUI environment. Passing an `.lproj`
            // sub-bundle back into `L10n.string` makes a second language lookup depend on the
            // system locale, so English overrides can incorrectly return Chinese resources.
            return Resolution(locale: locale, bundle: baseBundle)
        }
    }
}
