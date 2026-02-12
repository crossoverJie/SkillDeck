import XCTest
@testable import SkillDeck

/// GitService 的单元测试
///
/// 主要测试 URL 规范化逻辑（纯逻辑，不需要网络或 git）
/// 使用 XCTest 框架（类似 JUnit / Go 的 testing 包）
final class GitServiceTests: XCTestCase {

    // MARK: - normalizeRepoURL Tests

    /// 测试 "owner/repo" 格式的 URL 规范化
    /// 输入：vercel-labs/skills
    /// 预期：repoURL = "https://github.com/vercel-labs/skills.git", source = "vercel-labs/skills"
    func testNormalizeRepoURL_ownerSlashRepo() throws {
        let (repoURL, source) = try GitService.normalizeRepoURL("vercel-labs/skills")

        XCTAssertEqual(repoURL, "https://github.com/vercel-labs/skills.git")
        XCTAssertEqual(source, "vercel-labs/skills")
    }

    /// 测试完整 HTTPS URL 的规范化
    /// 输入：https://github.com/vercel-labs/skills
    /// 预期：repoURL 添加 .git 后缀，source 提取 owner/repo
    func testNormalizeRepoURL_fullHTTPS() throws {
        let (repoURL, source) = try GitService.normalizeRepoURL("https://github.com/vercel-labs/skills")

        XCTAssertEqual(repoURL, "https://github.com/vercel-labs/skills.git")
        XCTAssertEqual(source, "vercel-labs/skills")
    }

    /// 测试已带 .git 后缀的 URL
    /// 输入：https://github.com/vercel-labs/skills.git
    /// 预期：保持原样，source 去掉 .git 后缀
    func testNormalizeRepoURL_withDotGit() throws {
        let (repoURL, source) = try GitService.normalizeRepoURL("https://github.com/vercel-labs/skills.git")

        XCTAssertEqual(repoURL, "https://github.com/vercel-labs/skills.git")
        XCTAssertEqual(source, "vercel-labs/skills")
    }

    /// 测试带末尾斜杠的 URL
    /// 输入：https://github.com/vercel-labs/skills/
    /// 预期：正确处理末尾斜杠
    func testNormalizeRepoURL_withTrailingSlash() throws {
        let (repoURL, source) = try GitService.normalizeRepoURL("https://github.com/vercel-labs/skills/")

        XCTAssertEqual(repoURL, "https://github.com/vercel-labs/skills.git")
        XCTAssertEqual(source, "vercel-labs/skills")
    }

    /// 测试无效的 URL 输入
    /// 输入：空字符串、单个单词、多层路径
    /// 预期：抛出 invalidRepoURL 错误
    func testNormalizeRepoURL_invalid() {
        // 空字符串
        XCTAssertThrowsError(try GitService.normalizeRepoURL("")) { error in
            // 验证错误类型是 GitError.invalidRepoURL
            // `as?` 是 Swift 的类型安全转换（类似 Java 的 instanceof + 强转）
            guard case GitService.GitError.invalidRepoURL = error else {
                XCTFail("Expected invalidRepoURL error, got: \(error)")
                return
            }
        }

        // 单个单词（无 /）
        XCTAssertThrowsError(try GitService.normalizeRepoURL("justarepo")) { error in
            guard case GitService.GitError.invalidRepoURL = error else {
                XCTFail("Expected invalidRepoURL error, got: \(error)")
                return
            }
        }

        // 多层路径（超过 owner/repo）
        XCTAssertThrowsError(try GitService.normalizeRepoURL("a/b/c")) { error in
            guard case GitService.GitError.invalidRepoURL = error else {
                XCTFail("Expected invalidRepoURL error, got: \(error)")
                return
            }
        }
    }

    /// 测试带空格的输入（应自动 trim）
    func testNormalizeRepoURL_withWhitespace() throws {
        let (repoURL, source) = try GitService.normalizeRepoURL("  vercel-labs/skills  ")

        XCTAssertEqual(repoURL, "https://github.com/vercel-labs/skills.git")
        XCTAssertEqual(source, "vercel-labs/skills")
    }

    /// 测试 owner/repo.git 格式（owner/repo 带 .git 后缀）
    func testNormalizeRepoURL_ownerSlashRepoWithDotGit() throws {
        let (repoURL, source) = try GitService.normalizeRepoURL("vercel-labs/skills.git")

        XCTAssertEqual(repoURL, "https://github.com/vercel-labs/skills.git")
        XCTAssertEqual(source, "vercel-labs/skills")
    }
}
