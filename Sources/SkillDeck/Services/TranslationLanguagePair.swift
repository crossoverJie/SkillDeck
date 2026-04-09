import Foundation

#if canImport(Translation)
import Translation
#endif

/// Centralized source/target `Locale.Language` values for Apple's Translation framework.
///
/// This is intentionally separate from `AppLanguage`: the app stores generic UI language tags
/// such as `en` and `zh-Hans`, while the Translation framework needs one canonical pair that both
/// availability checks and real translation sessions can share.
struct TranslationLanguagePair {
    let source: Locale.Language

    let target: Locale.Language

    /// English (United States) → Simplified Chinese.
    ///
    /// We use `en-US` here instead of the broader UI tag `en` so the translation subsystem asks
    /// Apple's framework for one explicit, shared pair instead of duplicating ad-hoc identifiers.
    static let englishToSimplifiedChinese = TranslationLanguagePair(
        source: Locale.Language(identifier: "en-US"),
        target: Locale.Language(identifier: "zh-Hans")
    )
}
