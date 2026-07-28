import Foundation
import XCTest

@testable import SkillDeck

final class LocalizationLookupTests: XCTestCase {
    func testSettingsTabGeneral_isLocalizedInEnglish() {
        let key = L10nKeys.settingsTabGeneral
        let result = L10n.string(key, bundle: SkillDeckResources.bundle, locale: Locale(identifier: "en"))

        XCTAssertEqual(result, "General")
    }

    func testSettingsTabGeneral_isLocalizedInSimplifiedChinese() {
        let key = L10nKeys.settingsTabGeneral
        let result = L10n.string(key, bundle: SkillDeckResources.bundle, locale: Locale(identifier: "zh-Hans"))

        XCTAssertEqual(result, "通用")
    }

    func testSettingsTabGeneral_isLocalizedInSimplifiedChineseRegionLocale() {
        let key = L10nKeys.settingsTabGeneral
        let result = L10n.string(key, bundle: SkillDeckResources.bundle, locale: Locale(identifier: "zh_CN"))

        XCTAssertEqual(result, "通用")
    }

    func testNewProjectSyncKeys_areLocalizedWhenEnglishIsSelected() {
        let resolution = LocalizationResolver.resolve(language: .english)

        XCTAssertEqual(
            L10n.string(L10nKeys.sidebarGlobalSync, bundle: resolution.bundle, locale: resolution.locale),
            "Global Sync"
        )
        XCTAssertEqual(
            L10n.string(L10nKeys.dashboardAll, bundle: resolution.bundle, locale: resolution.locale),
            "All"
        )
    }
}
