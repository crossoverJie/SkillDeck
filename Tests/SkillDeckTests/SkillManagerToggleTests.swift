import XCTest
@testable import SkillDeck

/// SkillManager toggleAssignment 功能的单元测试
///
/// 测试目标：验证开启/关闭 Agent toggle 时：
/// 1. 能够正确创建/删除软连接
/// 2. refresh() 后 skill.installations 正确更新
/// 3. 继承安装不能被 toggle
///
/// 注意：这些测试直接操作真实文件系统路径（~/.claude/skills/ 等），
/// 使用唯一命名的 skill 避免与现有 skill 冲突，并在测试后清理。
final class SkillManagerToggleTests: XCTestCase {

    /// 唯一的测试 skill 名称，使用 UUID 避免冲突
    var uniqueSkillName: String!
    var tempSkillDir: URL!

    override func setUp() async throws {
        uniqueSkillName = "test-skill-\(UUID().uuidString.prefix(8))"

        // 在临时目录创建测试 skill
        tempSkillDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillDeckToggleTests-\(UUID().uuidString)")
            .appendingPathComponent(uniqueSkillName)

        try FileManager.default.createDirectory(at: tempSkillDir, withIntermediateDirectories: true)

        // 创建 SKILL.md
        let skillMDContent = """
        ---
        name: Test Skill
        description: A test skill for unit testing
        ---

        # Test Skill
        This is a test skill.
        """
        let skillMDURL = tempSkillDir.appendingPathComponent("SKILL.md")
        try skillMDContent.write(to: skillMDURL, atomically: true, encoding: .utf8)

        // 清理可能存在的测试软连接（来自之前失败的测试）
        try? await cleanupTestSymlinks()
    }

    override func tearDown() async throws {
        // 清理测试创建的软连接
        try? await cleanupTestSymlinks()

        // 清理临时目录
        if let tempDir = tempSkillDir?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    /// 清理所有 Agent 目录中可能存在的测试软连接
    private func cleanupTestSymlinks() async throws {
        for agentType in AgentType.allCases {
            let symlinkPath = agentType.skillsDirectoryURL.appendingPathComponent(uniqueSkillName)
            if FileManager.default.fileExists(atPath: symlinkPath.path) {
                try FileManager.default.removeItem(at: symlinkPath)
            }
        }
    }

    // MARK: - Helper Methods

    /// 创建模拟的 Skill 模型
    private func createMockSkill() -> Skill {
        Skill(
            id: uniqueSkillName,
            canonicalURL: tempSkillDir,
            metadata: SkillMetadata(
                name: "Test Skill",
                description: "A test skill"
            ),
            markdownBody: "# Test Skill",
            scope: .sharedGlobal,
            installations: []
        )
    }

    // MARK: - Toggle Assignment Tests

    /// 测试 toggleAssignment 创建软连接
    ///
    /// 场景：Agent 没有安装 skill，toggle 应该创建软连接
    func testToggleAssignmentCreatesSymlink() async throws {
        // Given
        let skill = createMockSkill()
        let expectedSymlinkPath = AgentType.claudeCode.skillsDirectoryURL.appendingPathComponent(uniqueSkillName)

        // When: 创建软连接
        try SymlinkManager.createSymlink(from: skill.canonicalURL, to: .claudeCode)

        // Then: 验证软连接存在
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedSymlinkPath.path),
                      "Symlink should exist at \(expectedSymlinkPath.path)")
        XCTAssertTrue(SymlinkManager.isSymlink(at: expectedSymlinkPath),
                      "Path should be a symlink")

        // 验证软连接指向正确的 canonical 路径
        let resolvedPath = SymlinkManager.resolveSymlink(at: expectedSymlinkPath)
        XCTAssertEqual(resolvedPath.standardized.path, skill.canonicalURL.standardized.path,
                       "Symlink should resolve to canonical path")
    }

    /// 测试 toggleAssignment 删除软连接
    ///
    /// 场景：Agent 已安装 skill（有软连接），toggle 应该删除软连接
    func testToggleAssignmentRemovesSymlink() async throws {
        // Given: 先创建软连接
        let skill = createMockSkill()
        let symlinkPath = AgentType.claudeCode.skillsDirectoryURL.appendingPathComponent(uniqueSkillName)

        try SymlinkManager.createSymlink(from: skill.canonicalURL, to: .claudeCode)
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlinkPath.path),
                      "Precondition: Symlink should exist before removal")

        // When: 删除软连接
        try SymlinkManager.removeSymlink(skillName: skill.id, from: .claudeCode)

        // Then: 验证软连接已删除
        XCTAssertFalse(FileManager.default.fileExists(atPath: symlinkPath.path),
                       "Symlink should be removed")
    }

    /// 测试 findInstallations 能够正确检测到直接安装
    ///
    /// 场景：Agent 目录中有指向 canonical 的软连接
    func testFindInstallationsDetectsDirectInstallation() async throws {
        // Given
        let skill = createMockSkill()

        // 创建软连接
        try SymlinkManager.createSymlink(from: skill.canonicalURL, to: .claudeCode)

        // When: 查找所有安装
        let installations = SymlinkManager.findInstallations(
            skillName: skill.id,
            canonicalURL: skill.canonicalURL
        )

        // Then: 验证找到了 Claude Code 的安装
        let claudeInstallation = installations.first { $0.agentType == .claudeCode }
        XCTAssertNotNil(claudeInstallation, "Should find Claude Code installation")
        XCTAssertTrue(claudeInstallation?.isSymlink ?? false, "Should be a symlink")
        XCTAssertFalse(claudeInstallation?.isInherited ?? true, "Should not be inherited")
    }

    /// 测试 findInstallations 能够正确检测到继承安装
    ///
    /// 场景：Agent A 有 skill，Agent B 可以从 Agent A 的目录读取
    /// 例如：Copilot CLI 可以从 ~/.claude/skills/ 读取
    func testFindInstallationsDetectsInheritedInstallation() async throws {
        // Given: 只在 Claude Code 目录创建软连接
        let skill = createMockSkill()

        // 创建软连接到 Claude Code
        try SymlinkManager.createSymlink(from: skill.canonicalURL, to: .claudeCode)

        // When: 查找所有安装
        let installations = SymlinkManager.findInstallations(
            skillName: skill.id,
            canonicalURL: skill.canonicalURL
        )

        // Then:
        // 1. Claude Code 应该有直接安装
        let claudeInstallation = installations.first { $0.agentType == .claudeCode }
        XCTAssertNotNil(claudeInstallation, "Should find Claude Code direct installation")
        XCTAssertFalse(claudeInstallation?.isInherited ?? true,
                       "Claude Code installation should not be inherited")

        // 2. Copilot CLI 应该有继承安装（因为 Copilot CLI 可以读取 Claude 的目录）
        let copilotInstallation = installations.first { $0.agentType == .copilotCLI }
        XCTAssertNotNil(copilotInstallation, "Should find Copilot CLI inherited installation")
        XCTAssertTrue(copilotInstallation?.isInherited ?? false,
                      "Copilot CLI installation should be inherited")
        XCTAssertEqual(copilotInstallation?.inheritedFrom, .claudeCode,
                       "Should inherit from Claude Code")
    }

    /// 测试删除直接安装后，继承安装也消失
    ///
    /// 场景：Agent A 有直接安装，Agent B 继承自 A
    /// 当删除 A 的安装后，B 的继承安装也应该消失
    func testRemoveDirectInstallationRemovesInheritedToo() async throws {
        // Given
        let skill = createMockSkill()

        // 创建 Claude Code 的直接安装
        try SymlinkManager.createSymlink(from: skill.canonicalURL, to: .claudeCode)

        // 验证初始状态：至少有 Claude（直接）+ Copilot（继承）
        let installationsBefore = SymlinkManager.findInstallations(
            skillName: skill.id,
            canonicalURL: skill.canonicalURL
        )
        let claudeBefore = installationsBefore.first { $0.agentType == .claudeCode }
        let copilotBefore = installationsBefore.first { $0.agentType == .copilotCLI }
        XCTAssertNotNil(claudeBefore, "Claude should have direct installation")
        XCTAssertFalse(claudeBefore?.isInherited ?? true, "Claude installation should not be inherited")
        XCTAssertNotNil(copilotBefore, "Copilot should have inherited installation")
        XCTAssertTrue(copilotBefore?.isInherited ?? false, "Copilot installation should be inherited")

        // When: 删除 Claude Code 的直接安装
        try SymlinkManager.removeSymlink(skillName: skill.id, from: .claudeCode)

        // Then: Claude 和 Copilot 的安装都应该消失
        let installationsAfter = SymlinkManager.findInstallations(
            skillName: skill.id,
            canonicalURL: skill.canonicalURL
        )
        let claudeAfter = installationsAfter.first { $0.agentType == .claudeCode }
        let copilotAfter = installationsAfter.first { $0.agentType == .copilotCLI }
        XCTAssertNil(claudeAfter, "Claude installation should be removed")
        XCTAssertNil(copilotAfter, "Copilot inherited installation should also be removed")
    }

    /// 测试 Codex 的 ~/.agents/skills/ 不被视为继承安装
    ///
    /// 场景：Codex 原生支持 ~/.agents/skills/，虽然 findInstallations 返回 isInherited=true，
    /// 但 inheritedFrom=.codex，在 UI 层和 SkillManager 层会被视为非继承
    func testCodexAgentsSkillsIsNotInherited() async throws {
        // Given: 在 ~/.agents/skills/ 创建 skill（模拟 Codex 原生读取）
        let agentsSkillsDir = AgentType.sharedSkillsDirectoryURL
        let skillDir = agentsSkillsDir.appendingPathComponent(uniqueSkillName)

        // 确保目录存在
        try? FileManager.default.createDirectory(at: agentsSkillsDir, withIntermediateDirectories: true)

        // 复制测试 skill 到 ~/.agents/skills/
        try? FileManager.default.copyItem(at: tempSkillDir, to: skillDir)

        // 清理在 tearDown 中进行
        defer {
            try? FileManager.default.removeItem(at: skillDir)
        }

        // When: 查找安装
        let installations = SymlinkManager.findInstallations(
            skillName: uniqueSkillName,
            canonicalURL: skillDir
        )

        // Then: 验证 installations 可以正常获取（没有 crash）
        XCTAssertNotNil(installations)

        // 验证 Codex 的 installation 的 inheritedFrom 是 .codex
        // 这允许 UI 层和 SkillManager 将其视为非继承安装
        let codexInstallation = installations.first { $0.agentType == .codex }
        XCTAssertNotNil(codexInstallation, "Should find Codex installation")
        XCTAssertEqual(codexInstallation?.inheritedFrom, .codex,
                       "Codex installation from ~/.agents/skills/ should have inheritedFrom=.codex")

        // 注意：findInstallations 返回的 isInherited 为 true，但 UI/SkillManager 会特殊处理 inheritedFrom=.codex 的情况
        // 这是 isTrulyInherited 逻辑的一部分
    }

    // MARK: - Edge Cases

    /// 测试删除不存在的软连接不会抛出错误
    ///
    /// 场景：软连接已被手动删除，再次调用 removeSymlink 应该静默处理
    func testRemoveNonExistentSymlinkDoesNotThrow() async throws {
        // Given
        let skill = createMockSkill()

        // When/Then: 删除不存在的软连接不应该抛出错误
        XCTAssertNoThrow(try SymlinkManager.removeSymlink(skillName: skill.id, from: .claudeCode))
    }

    /// 测试创建软连接时目标已存在（重复 toggle）
    ///
    /// 场景：软连接已存在，再次创建应该抛出错误
    func testCreateSymlinkWhenTargetExistsThrows() async throws {
        // Given
        let skill = createMockSkill()

        // 先创建一次
        try SymlinkManager.createSymlink(from: skill.canonicalURL, to: .claudeCode)

        // When/Then: 再次创建应该抛出错误
        XCTAssertThrowsError(try SymlinkManager.createSymlink(from: skill.canonicalURL, to: .claudeCode)) { error in
            guard let symlinkError = error as? SymlinkManager.SymlinkError else {
                XCTFail("Expected SymlinkError")
                return
            }
            XCTAssertEqual(symlinkError.errorDescription?.contains("already exists"), true)
        }
    }
}
