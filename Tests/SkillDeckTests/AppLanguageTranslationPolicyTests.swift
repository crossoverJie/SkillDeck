import XCTest
@testable import SkillDeck

final class AppLanguageTranslationPolicyTests: XCTestCase {

    func testShouldTranslateSkillContent_whenEnglishUI_isFalse() {
        XCTAssertFalse(AppLanguage.english.shouldTranslateSkillContent(locale: Locale(identifier: "en_US")))
    }

    func testShouldTranslateSkillContent_whenSimplifiedChineseUI_isFalse() {
        XCTAssertTrue(AppLanguage.simplifiedChinese.shouldTranslateSkillContent(locale: Locale(identifier: "zh_Hans_CN")))
    }

    func testShouldTranslateSkillContent_whenSystemAndEnglishLocale_isFalse() {
        XCTAssertFalse(AppLanguage.system.shouldTranslateSkillContent(locale: Locale(identifier: "en_US")))
    }

    func testShouldTranslateSkillContent_whenSystemAndChineseLocale_isTrue() {
        XCTAssertTrue(AppLanguage.system.shouldTranslateSkillContent(locale: Locale(identifier: "zh_Hans_CN")))
    }
}
