import XCTest
@testable import SkillDeck

final class SettingsWindowSizingTests: XCTestCase {
    func testMinWindowSizeScalesWithFontSize() {
        let base = SettingsWindowSizing.minSize(forFontSize: 13)
        let larger = SettingsWindowSizing.minSize(forFontSize: 20)

        XCTAssertGreaterThan(larger.width, base.width)
        XCTAssertGreaterThan(larger.height, base.height)
    }

    func testMinWindowSizeClampsToMinimums() {
        let tiny = SettingsWindowSizing.minSize(forFontSize: 8)
        XCTAssertEqual(tiny.width, SettingsWindowSizing.baseWidth)
        XCTAssertEqual(tiny.height, SettingsWindowSizing.baseHeight)
    }
}
