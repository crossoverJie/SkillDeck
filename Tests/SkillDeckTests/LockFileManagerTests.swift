import XCTest
@testable import SkillDeck

/// LockFileManager 的单元测试
///
/// 测试策略：使用临时文件，避免修改真实的 lock file
/// setUp() 创建临时文件，tearDown() 清理
final class LockFileManagerTests: XCTestCase {

    /// 临时文件路径
    var tempURL: URL!
    /// 被测对象
    var manager: LockFileManager!

    /// setUp 在每个测试方法执行前调用（类似 JUnit 的 @Before）
    override func setUp() async throws {
        // 创建临时目录和文件
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempURL = tempDir.appendingPathComponent(".skill-lock.json")

        // 写入测试用的 lock file 数据
        let testLockFile = LockFile(
            version: 3,
            skills: [
                "agent-notifier": LockEntry(
                    source: "crossoverJie/skills",
                    sourceType: "github",
                    sourceUrl: "https://github.com/crossoverJie/skills.git",
                    skillPath: "skills/agent-notifier/SKILL.md",
                    skillFolderHash: "abc123",
                    installedAt: "2026-02-07T08:07:27.280Z",
                    updatedAt: "2026-02-07T08:07:27.280Z"
                ),
                "prompt-engineering": LockEntry(
                    source: "inference-sh/skills",
                    sourceType: "github",
                    sourceUrl: "https://github.com/inference-sh/skills.git",
                    skillPath: "skills/prompt-engineering/SKILL.md",
                    skillFolderHash: "def456",
                    installedAt: "2026-02-05T07:18:32.300Z",
                    updatedAt: "2026-02-05T07:18:32.300Z"
                ),
            ],
            dismissed: ["findSkillsPrompt": true],
            lastSelectedAgents: ["claude-code", "codex"]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(testLockFile)
        try data.write(to: tempURL)

        // 使用临时文件路径创建 manager
        manager = LockFileManager(filePath: tempURL)
    }

    /// tearDown 在每个测试方法执行后调用（类似 JUnit 的 @After）
    override func tearDown() async throws {
        // 清理临时文件
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
        manager = nil
        tempURL = nil
    }

    // MARK: - Read Tests

    /// 测试读取 lock file
    func testRead() async throws {
        let lockFile = try await manager.read()

        XCTAssertEqual(lockFile.version, 3)
        XCTAssertEqual(lockFile.skills.count, 2)
        XCTAssertNotNil(lockFile.skills["agent-notifier"])
        XCTAssertNotNil(lockFile.skills["prompt-engineering"])
    }

    /// 测试获取单个 entry
    func testGetEntry() async throws {
        let entry = try await manager.getEntry(skillName: "agent-notifier")

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.source, "crossoverJie/skills")
        XCTAssertEqual(entry?.sourceType, "github")
        XCTAssertEqual(entry?.skillFolderHash, "abc123")
    }

    /// 测试获取不存在的 entry
    func testGetNonExistentEntry() async throws {
        let entry = try await manager.getEntry(skillName: "non-existent")
        XCTAssertNil(entry)
    }

    // MARK: - Write Tests

    /// 测试更新 entry
    func testUpdateEntry() async throws {
        let newEntry = LockEntry(
            source: "test/repo",
            sourceType: "github",
            sourceUrl: "https://github.com/test/repo.git",
            skillPath: "skills/new-skill/SKILL.md",
            skillFolderHash: "xyz789",
            installedAt: "2026-02-10T00:00:00.000Z",
            updatedAt: "2026-02-10T00:00:00.000Z"
        )

        try await manager.updateEntry(skillName: "new-skill", entry: newEntry)

        // 清除缓存后重新读取，验证持久化成功
        await manager.invalidateCache()
        let lockFile = try await manager.read()
        XCTAssertEqual(lockFile.skills.count, 3)
        XCTAssertEqual(lockFile.skills["new-skill"]?.source, "test/repo")
    }

    /// 测试删除 entry
    func testRemoveEntry() async throws {
        try await manager.removeEntry(skillName: "agent-notifier")

        await manager.invalidateCache()
        let lockFile = try await manager.read()
        XCTAssertEqual(lockFile.skills.count, 1)
        XCTAssertNil(lockFile.skills["agent-notifier"])
        // 其他 entry 不受影响
        XCTAssertNotNil(lockFile.skills["prompt-engineering"])
    }

    // MARK: - Edge Cases

    /// 测试 version 和 dismissed 字段保留
    func testPreservesOtherFields() async throws {
        let newEntry = LockEntry(
            source: "a/b",
            sourceType: "github",
            sourceUrl: "https://github.com/a/b.git",
            skillPath: "skills/c/SKILL.md",
            skillFolderHash: "000",
            installedAt: "2026-01-01T00:00:00.000Z",
            updatedAt: "2026-01-01T00:00:00.000Z"
        )

        try await manager.updateEntry(skillName: "c", entry: newEntry)

        await manager.invalidateCache()
        let lockFile = try await manager.read()

        // 验证 version、dismissed、lastSelectedAgents 未被修改
        XCTAssertEqual(lockFile.version, 3)
        XCTAssertEqual(lockFile.dismissed?["findSkillsPrompt"], true)
        XCTAssertEqual(lockFile.lastSelectedAgents, ["claude-code", "codex"])
    }

    /// 测试文件不存在时的行为
    func testFileNotFound() async {
        let badManager = LockFileManager(
            filePath: URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).json")
        )

        do {
            _ = try await badManager.read()
            XCTFail("Expected error for missing file")
        } catch {
            // 预期的错误 ✓
        }
    }
}
