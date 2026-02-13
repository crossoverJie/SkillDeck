import XCTest
@testable import SkillDeck

/// VersionComparator 的单元测试
///
/// 测试覆盖：
/// - parse()：标准版本、v 前缀、两段版本、预发布后缀、无效输入
/// - isNewer()：patch/minor/major 更新、相同版本、旧版本、不同段数
final class VersionComparatorTests: XCTestCase {

    // MARK: - parse() 测试

    /// 测试标准三段版本号解析
    func testParseStandardVersion() {
        let result = VersionComparator.parse("1.2.3")
        XCTAssertEqual(result, [1, 2, 3])
    }

    /// 测试带 "v" 前缀的版本号
    func testParseWithVPrefix() {
        let result = VersionComparator.parse("v1.2.3")
        XCTAssertEqual(result, [1, 2, 3])
    }

    /// 测试大写 "V" 前缀
    func testParseWithUppercaseVPrefix() {
        let result = VersionComparator.parse("V2.0.0")
        XCTAssertEqual(result, [2, 0, 0])
    }

    /// 测试两段版本号（如 "1.0"）
    func testParseTwoSegments() {
        let result = VersionComparator.parse("1.0")
        XCTAssertEqual(result, [1, 0])
    }

    /// 测试带预发布后缀的版本号
    func testParseWithPreReleaseSuffix() {
        let result = VersionComparator.parse("1.0.0-beta")
        XCTAssertEqual(result, [1, 0, 0])
    }

    /// 测试带复杂预发布后缀的版本号
    func testParseWithComplexPreReleaseSuffix() {
        let result = VersionComparator.parse("2.1.0-rc.1")
        XCTAssertEqual(result, [2, 1, 0])
    }

    /// 测试 "dev" 版本（非数字，应返回空数组）
    func testParseDevVersion() {
        let result = VersionComparator.parse("dev")
        XCTAssertEqual(result, [])
    }

    /// 测试空字符串
    func testParseEmptyString() {
        let result = VersionComparator.parse("")
        XCTAssertEqual(result, [])
    }

    /// 测试只有 "v" 前缀
    func testParseOnlyV() {
        let result = VersionComparator.parse("v")
        XCTAssertEqual(result, [])
    }

    // MARK: - isNewer() 测试

    /// 测试 patch 版本更新（1.0.0 → 1.0.1）
    func testIsNewerPatchUpdate() {
        XCTAssertTrue(VersionComparator.isNewer(current: "1.0.0", latest: "1.0.1"))
    }

    /// 测试 minor 版本更新（1.0.0 → 1.1.0）
    func testIsNewerMinorUpdate() {
        XCTAssertTrue(VersionComparator.isNewer(current: "1.0.0", latest: "1.1.0"))
    }

    /// 测试 major 版本更新（1.0.0 → 2.0.0）
    func testIsNewerMajorUpdate() {
        XCTAssertTrue(VersionComparator.isNewer(current: "1.0.0", latest: "2.0.0"))
    }

    /// 测试相同版本（不应报告更新）
    func testIsNewerSameVersion() {
        XCTAssertFalse(VersionComparator.isNewer(current: "1.0.0", latest: "1.0.0"))
    }

    /// 测试旧版本（latest 比 current 更旧）
    func testIsNewerOlderVersion() {
        XCTAssertFalse(VersionComparator.isNewer(current: "2.0.0", latest: "1.9.9"))
    }

    /// 测试带 "v" 前缀的版本比较
    func testIsNewerWithVPrefix() {
        XCTAssertTrue(VersionComparator.isNewer(current: "v1.0.0", latest: "v1.0.1"))
    }

    /// 测试不同段数的版本比较（"1.0" vs "1.0.1"）
    func testIsNewerDifferentSegmentCount() {
        XCTAssertTrue(VersionComparator.isNewer(current: "1.0", latest: "1.0.1"))
    }

    /// 测试两段相同版本（"1.0" 等价于 "1.0.0"）
    func testIsNewerTwoSegmentsSame() {
        XCTAssertFalse(VersionComparator.isNewer(current: "1.0", latest: "1.0.0"))
    }

    /// 测试带预发布后缀的版本比较（后缀被忽略，只比较数字部分）
    func testIsNewerWithPreRelease() {
        // "1.0.0-beta" 的数字部分是 [1, 0, 0]，与 "1.0.0" 相同
        XCTAssertFalse(VersionComparator.isNewer(current: "1.0.0-beta", latest: "1.0.0"))
        // "1.0.1" 的数字部分 [1, 0, 1] > [1, 0, 0]
        XCTAssertTrue(VersionComparator.isNewer(current: "1.0.0-beta", latest: "1.0.1"))
    }

    /// 测试 "dev" 版本（空数组 vs 任何版本号，都应返回 true）
    func testIsNewerFromDev() {
        XCTAssertTrue(VersionComparator.isNewer(current: "dev", latest: "0.0.1"))
    }
}
