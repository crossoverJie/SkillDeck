import XCTest

@testable import SkillDeck

/// Tests for the i18n-related *settings primitives* used by the app.
///
/// Why this file name?
/// - The next tasks in this i18n workstream will add a "localization resolver" (logic that decides
///   which language resources to use).
/// - Task 1 only introduces the foundational types (`AppLanguage`, `LanguageSettings`).
///   Keeping the tests here avoids churn later when the resolver lands.
final class LocalizationResolverTests: XCTestCase {

    func testAppLanguage_rawValues_matchExpectedStorageValues() {
        // Swift enums can have "raw values". With `RawRepresentable`, Swift can serialize/deserialize
        // the enum to a primitive type (here: `String`).
        //
        // We intentionally test the raw values because these strings are persisted in UserDefaults.
        // If a raw value changes accidentally, the app would stop reading existing user preferences.
        XCTAssertEqual(AppLanguage.system.rawValue, "system")
        XCTAssertEqual(AppLanguage.english.rawValue, "en")
        XCTAssertEqual(AppLanguage.simplifiedChinese.rawValue, "zh-Hans")
    }

    func testAppLanguage_pickerTitles_matchExpectedUserFacingStrings() {
        // These titles are shown in a SwiftUI `Picker`.
        // We keep them centralized (rather than scattering literals across Views) so that:
        // 1) UI stays consistent
        // 2) future localization work can move these strings into Localizable.strings easily.
        XCTAssertEqual(AppLanguage.system.pickerTitle, "System Default")
        XCTAssertEqual(AppLanguage.english.pickerTitle, "English")
        XCTAssertEqual(AppLanguage.simplifiedChinese.pickerTitle, "中文")
    }

    func testAppLanguage_initFromStoredRawValue_unknownFallsBackToSystem() {
        // When reading from storage we must be defensive.
        // - The stored string might be missing (nil)
        // - It might be from an older version
        // - A user could tamper with UserDefaults
        //
        // The requirement is: unknown raw values MUST safely fall back to `.system`.
        XCTAssertEqual(AppLanguage(storedRawValue: nil), .system)
        XCTAssertEqual(AppLanguage(storedRawValue: ""), .system)
        XCTAssertEqual(AppLanguage(storedRawValue: "unknown"), .system)
    }

    func testAppLanguage_initFromStoredRawValue_knownValuesRoundTrip() {
        // Known stored values should map back to the correct enum cases.
        XCTAssertEqual(AppLanguage(storedRawValue: "system"), .system)
        XCTAssertEqual(AppLanguage(storedRawValue: "en"), .english)
        XCTAssertEqual(AppLanguage(storedRawValue: "zh-Hans"), .simplifiedChinese)
    }

    func testLanguageSettings_usesStableUserDefaultsKey_andDefaultLanguage() {
        // Similar to FontSettings, we keep UserDefaults keys in a single place.
        // This reduces the risk of typos and makes migrations easier.
        XCTAssertEqual(LanguageSettings.appLanguageKey, "uiAppLanguage")
        XCTAssertEqual(LanguageSettings.defaultLanguage, .system)
    }

    func testLocalizationResolver_system_usesAutoupdatingLocale_andBaseBundle() {
        let baseBundle = SkillDeckResources.bundle

        let resolution = LocalizationResolver.resolve(language: .system, baseBundle: baseBundle)

        XCTAssertEqual(resolution.locale.identifier, Locale.autoupdatingCurrent.identifier)
        XCTAssertEqual(resolution.bundle.bundleURL, baseBundle.bundleURL)
    }

    func testLocalizationResolver_explicitEnglish_setsLocale_andFallsBackToBaseBundle_whenLprojMissing() {
        let baseBundle = SkillDeckResources.bundle

        let resolution = LocalizationResolver.resolve(language: .english, baseBundle: baseBundle)

        XCTAssertEqual(resolution.locale.identifier, Locale(identifier: AppLanguage.english.rawValue).identifier)

        let lprojPath = baseBundle.path(forResource: AppLanguage.english.rawValue, ofType: "lproj")
        if lprojPath == nil {
            XCTAssertEqual(resolution.bundle.bundleURL, baseBundle.bundleURL)
        } else {
            XCTAssertNotEqual(resolution.bundle.bundleURL, baseBundle.bundleURL)
            XCTAssertTrue(resolution.bundle.bundleURL.path.hasSuffix("\(AppLanguage.english.rawValue).lproj"))
        }
    }

    func testLocalizationResolver_explicitSimplifiedChinese_setsLocale_andFallsBackToBaseBundle_whenLprojMissing() {
        let baseBundle = SkillDeckResources.bundle

        let resolution = LocalizationResolver.resolve(language: .simplifiedChinese, baseBundle: baseBundle)

        XCTAssertEqual(
            resolution.locale.identifier,
            Locale(identifier: AppLanguage.simplifiedChinese.rawValue).identifier
        )

        let candidatePaths = [
            baseBundle.path(forResource: AppLanguage.simplifiedChinese.rawValue, ofType: "lproj"),
            baseBundle.path(forResource: AppLanguage.simplifiedChinese.rawValue.lowercased(), ofType: "lproj")
        ]

        if candidatePaths.allSatisfy({ $0 == nil }) {
            XCTAssertEqual(resolution.bundle.bundleURL, baseBundle.bundleURL)
        } else {
            XCTAssertNotEqual(resolution.bundle.bundleURL, baseBundle.bundleURL)
            let path = resolution.bundle.bundleURL.path.lowercased()
            XCTAssertTrue(path.hasSuffix("zh-hans.lproj") || path.hasSuffix("zh_hans.lproj"))
        }
    }
}
