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

    // MARK: - scanSkillsInRepo Tests

    /// Test that scanSkillsInRepo discovers SKILL.md inside hidden directories like `.claude/skills/`.
    ///
    /// Some repositories (e.g. nextlevelbuilder/ui-ux-pro-max-skill) store skills at
    /// `.claude/skills/<name>/SKILL.md`. Previously, `FileManager.enumerator` was created
    /// with `.skipsHiddenFiles`, which caused `.claude/` to be skipped entirely.
    /// This test verifies the fix: hidden directories are now traversed.
    func testScanSkillsInRepoFindsHiddenDirectorySkills() async throws {
        let fm = FileManager.default
        // Create a temporary directory simulating a cloned repo
        let repoDir = fm.temporaryDirectory.appendingPathComponent("SkillDeck-test-\(UUID().uuidString)")
        // Simulate `.claude/skills/my-skill/SKILL.md` layout
        let skillDir = repoDir
            .appendingPathComponent(".claude")
            .appendingPathComponent("skills")
            .appendingPathComponent("my-skill")
        try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)

        // Write a minimal SKILL.md with YAML frontmatter
        let skillMDContent = """
        ---
        name: my-skill
        description: A test skill in a hidden directory
        ---
        # My Skill
        Hello world
        """
        try skillMDContent.write(
            to: skillDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // `defer` ensures cleanup runs when the function exits (similar to Go's defer)
        defer { try? fm.removeItem(at: repoDir) }

        // GitService is an actor, so we need `await` to call its methods
        let gitService = GitService()
        let skills = await gitService.scanSkillsInRepo(repoDir: repoDir)

        // Should find exactly 1 skill
        XCTAssertEqual(skills.count, 1, "Expected 1 skill in hidden directory, found \(skills.count)")
        // Verify skill metadata
        let skill = try XCTUnwrap(skills.first)
        XCTAssertEqual(skill.id, "my-skill")
        XCTAssertEqual(skill.folderPath, ".claude/skills/my-skill")
        XCTAssertEqual(skill.skillMDPath, ".claude/skills/my-skill/SKILL.md")
    }

    /// Test that scanSkillsInRepo skips the `.git` directory when scanning.
    ///
    /// The `.git` directory is large and never contains real skills.
    /// After removing `.skipsHiddenFiles`, we manually skip `.git` to avoid
    /// false positives (e.g. a SKILL.md inside `.git/` should be ignored).
    func testScanSkillsInRepoSkipsGitDirectory() async throws {
        let fm = FileManager.default
        let repoDir = fm.temporaryDirectory.appendingPathComponent("SkillDeck-test-\(UUID().uuidString)")

        // Create a real skill at top level
        let realSkillDir = repoDir.appendingPathComponent("my-real-skill")
        try fm.createDirectory(at: realSkillDir, withIntermediateDirectories: true)
        let realContent = """
        ---
        name: my-real-skill
        description: A legitimate skill
        ---
        # Real Skill
        """
        try realContent.write(
            to: realSkillDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // Create a fake SKILL.md inside `.git/` — this should be ignored
        let gitDir = repoDir.appendingPathComponent(".git")
        try fm.createDirectory(at: gitDir, withIntermediateDirectories: true)
        let fakeContent = """
        ---
        name: fake-git-skill
        description: Should be ignored
        ---
        # Fake
        """
        try fakeContent.write(
            to: gitDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        defer { try? fm.removeItem(at: repoDir) }

        let gitService = GitService()
        let skills = await gitService.scanSkillsInRepo(repoDir: repoDir)

        // Should find only the real skill, not the one inside .git/
        XCTAssertEqual(skills.count, 1, "Expected 1 skill (should skip .git), found \(skills.count)")
        let skill = try XCTUnwrap(skills.first)
        XCTAssertEqual(skill.id, "my-real-skill")
    }
}
