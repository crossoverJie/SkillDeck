import XCTest

@testable import SkillDeck

/// Ensures every localization key used by the app exists in both supported languages.
///
/// This is important because missing translations typically fall back to returning the key itself.
final class L10nKeysCoverageTests: XCTestCase {

    func testAllKeysHaveEnglishAndSimplifiedChineseTranslations() {
        let baseBundle = SkillDeckResources.bundle

        let englishBundle = LocalizationResolver.resolve(language: .english, baseBundle: baseBundle).bundle
        let chineseBundle = LocalizationResolver.resolve(language: .simplifiedChinese, baseBundle: baseBundle).bundle

        for key in L10nKeys.allKeys {
            let en = englishBundle.localizedString(forKey: key, value: nil, table: nil)
            let zh = chineseBundle.localizedString(forKey: key, value: nil, table: nil)

            XCTAssertNotEqual(en, key, "Missing English translation for key: \(key)")
            XCTAssertNotEqual(zh, key, "Missing Simplified Chinese translation for key: \(key)")
        }
    }
}
