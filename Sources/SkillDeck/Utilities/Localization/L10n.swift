import Foundation

/// A tiny localization lookup helper.
///
/// Why does this exist when Swift already has `String(localized:bundle:locale:)`?
/// - Call sites in the app should not have to remember the exact Foundation API surface.
/// - Our unit tests want deterministic output: we pass an explicit `Bundle` (SwiftPM's
///   `Bundle.module` via `SkillDeckResources.bundle`) and an explicit `Locale`.
/// - If we ever need to change lookup behavior (e.g. custom tables, fallback chain), we do it here.
///
/// Design notes for readers coming from Java/Go/Python:
/// - This is an `enum` with only `static` members, used as a namespacing pattern.
///   Swift does not have packages in the Java sense, so this is a common way to group helpers.
enum L10n {
    static func string(
        _ key: String,
        bundle: Bundle,
        locale: Locale
    ) -> String {
        if let localizedBundle = localizedBundle(for: locale, in: bundle) {
            let manual = localizedBundle.localizedString(forKey: key, value: nil, table: nil)
            if manual != key {
                return manual
            }
        }

        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// Returns a localized string for `key` in `bundle`, using `locale`.
    ///
    /// We *prefer* the modern API:
    /// `String(localized: key, bundle: bundle, locale: locale)`
    ///
    /// Fallback:
    /// Some toolchains / build setups have historically had issues with locale-specific
    /// lookups when resources are packaged in a SwiftPM `Bundle.module`. As a defensive
    /// fallback, if the modern API appears to return the raw key, we manually select the
    /// `.lproj` bundle for the requested locale and use `Bundle.localizedString(...)`.
    ///
    /// The fallback requires extracting the underlying key string from `String.LocalizationValue`.
    /// That type is intentionally opaque; we use `Mirror` (reflection) only on the fallback path.
    static func string(
        _ key: String.LocalizationValue,
        bundle: Bundle,
        locale: Locale
    ) -> String {
        let rawKey = localizationKeyString(key)

        // Prefer the modern API. This is the intended, locale-aware call.
        //
        // However, in some SwiftPM/toolchain combinations the `locale` parameter can be ignored
        // when resources live in `Bundle.module` (the unit test in this repo reproduces this).
        // To keep behavior deterministic, we ALSO attempt a manual `.lproj` bundle lookup.
        let preferred = String(localized: key, bundle: bundle, locale: locale)

        if !rawKey.isEmpty {
            return string(rawKey, bundle: bundle, locale: locale)
        }

        return preferred
    }

    /// Best-effort conversion from `String.LocalizationValue` to its underlying key string.
    ///
    /// `String.LocalizationValue` prints as `LocalizationValue(..., key: "...")`, so we cannot
    /// reliably extract the key via `String(describing:)`. `Mirror` exposes the stored `key` field.
    private static func localizationKeyString(_ key: String.LocalizationValue) -> String {
        for child in Mirror(reflecting: key).children {
            if child.label == "key", let value = child.value as? String {
                return value
            }
        }

        // If reflection ever changes (future Swift), return an empty string.
        // This keeps the method total (non-throwing) and makes failures obvious in tests.
        return ""
    }

    /// Returns a locale-specific `.lproj` bundle inside `bundle`.
    ///
    /// `Locale.identifier` is usually BCP-47-like (e.g. `zh-Hans`, `en_US`). `.lproj` folder names
    /// on Apple platforms typically use hyphenated identifiers (`zh-Hans`, `en`).
    private static func localizedBundle(for locale: Locale, in bundle: Bundle) -> Bundle? {
        // Candidate names to try, in order.
        // We try the full identifier first, then normalized variants, then just the language code.
        var candidates: [String] = []

        let identifier = locale.identifier
        candidates.append(identifier)
        candidates.append(identifier.replacingOccurrences(of: "_", with: "-"))
        candidates.append(identifier.lowercased())
        candidates.append(identifier.replacingOccurrences(of: "_", with: "-").lowercased())

        let normalizedIdentifier = identifier.replacingOccurrences(of: "_", with: "-")
        let parts = normalizedIdentifier.split(separator: "-").map(String.init)
        if parts.count >= 2 {
            candidates.append("\(parts[0])\u{002D}\(parts[1])")
            candidates.append("\(parts[0])_\(parts[1])")
            candidates.append("\(parts[0])\u{002D}\(parts[1])".lowercased())
            candidates.append("\(parts[0])_\(parts[1])".lowercased())
        }

        if let languageCode = locale.language.languageCode?.identifier,
           let scriptCode = locale.language.script?.identifier {
            candidates.append("\(languageCode)-\(scriptCode)")
            candidates.append("\(languageCode)_\(scriptCode)")
            candidates.append("\(languageCode)-\(scriptCode)".lowercased())
            candidates.append("\(languageCode)_\(scriptCode)".lowercased())
        }

        // `Locale.languageCode` was deprecated; the modern API is `locale.language.languageCode?.identifier`.
        if let languageCode = locale.language.languageCode?.identifier {
            candidates.append(languageCode)
            candidates.append(languageCode.lowercased())
        }

        var deduplicated: [String] = []
        for candidate in candidates where !deduplicated.contains(candidate) {
            deduplicated.append(candidate)
        }

        for name in deduplicated {
            if let path = bundle.path(forResource: name, ofType: "lproj"), let lprojBundle = Bundle(path: path) {
                return lprojBundle
            }
        }

        return nil
    }
}
