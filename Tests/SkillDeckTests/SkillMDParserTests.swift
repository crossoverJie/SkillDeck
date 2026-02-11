import XCTest
@testable import SkillDeck

/// SkillMDParser 的单元测试
///
/// Swift 使用 XCTest 框架进行测试（类似 JUnit / Go 的 testing 包）：
/// - 测试类继承 XCTestCase
/// - 测试方法以 test 开头
/// - 使用 XCTAssert* 系列断言方法（类似 JUnit 的 Assert.*）
/// - 运行方式：swift test 或 Xcode 中 Cmd+U
final class SkillMDParserTests: XCTestCase {

    // MARK: - 正常解析测试

    /// 测试标准的 SKILL.md 格式解析
    func testParseStandardSkillMD() throws {
        // arrange：准备测试数据
        let content = """
        ---
        name: agent-notifier
        description: >
          Multi-platform notification skill for AI agents.
        license: Apache-2.0
        metadata:
          author: crossoverJie
          version: "1.0"
        ---

        # Agent Notifier Skill

        This skill sends notifications.
        """

        // act：执行被测方法
        // `try` 表示方法可能抛出异常，在测试中使用 throws 方法签名来传播异常
        let result = try SkillMDParser.parse(content: content)

        // assert：验证结果
        XCTAssertEqual(result.metadata.name, "agent-notifier")
        XCTAssertTrue(result.metadata.description.contains("Multi-platform"))
        XCTAssertEqual(result.metadata.license, "Apache-2.0")
        XCTAssertEqual(result.metadata.author, "crossoverJie")
        XCTAssertEqual(result.metadata.version, "1.0")
        XCTAssertTrue(result.markdownBody.contains("# Agent Notifier Skill"))
    }

    /// 测试带 allowed-tools 字段的解析
    func testParseWithAllowedTools() throws {
        let content = """
        ---
        name: prompt-engineering
        description: Prompt engineering guide
        allowed-tools: Bash(infsh *)
        ---

        # Guide
        """

        let result = try SkillMDParser.parse(content: content)

        XCTAssertEqual(result.metadata.name, "prompt-engineering")
        XCTAssertEqual(result.metadata.allowedTools, "Bash(infsh *)")
    }

    /// 测试最小化的 SKILL.md（只有必填字段）
    func testParseMinimalSkillMD() throws {
        let content = """
        ---
        name: minimal-skill
        description: A minimal skill
        ---

        Content here.
        """

        let result = try SkillMDParser.parse(content: content)

        XCTAssertEqual(result.metadata.name, "minimal-skill")
        XCTAssertEqual(result.metadata.description, "A minimal skill")
        XCTAssertNil(result.metadata.license)
        XCTAssertNil(result.metadata.author)
        XCTAssertNil(result.metadata.version)
        XCTAssertEqual(result.markdownBody, "Content here.")
    }

    // MARK: - 错误处理测试

    /// 测试没有 frontmatter 分隔符的情况
    func testParseNoFrontmatter() {
        let content = "# Just Markdown\n\nNo frontmatter here."

        // XCTAssertThrowsError：验证方法是否抛出了预期的异常
        // 类似 JUnit 的 assertThrows 或 Go 的 if err == nil { t.Fatal() }
        XCTAssertThrowsError(try SkillMDParser.parse(content: content)) { error in
            // 验证错误类型
            guard let parseError = error as? SkillMDParser.ParseError else {
                XCTFail("Expected ParseError but got \(error)")
                return
            }
            if case .noFrontmatter = parseError {
                // 正确的错误类型 ✓
            } else {
                XCTFail("Expected .noFrontmatter but got \(parseError)")
            }
        }
    }

    /// 测试只有一个 --- 分隔符的情况
    func testParseSingleSeparator() {
        let content = "---\nname: broken\n"

        XCTAssertThrowsError(try SkillMDParser.parse(content: content))
    }

    // MARK: - 序列化测试

    /// 测试 metadata + body 序列化回 SKILL.md 格式
    func testSerialize() throws {
        let metadata = SkillMetadata(
            name: "test-skill",
            description: "A test skill",
            license: "MIT",
            metadata: SkillMetadata.MetadataExtra(author: "tester", version: "2.0")
        )

        let result = try SkillMDParser.serialize(metadata: metadata, markdownBody: "# Hello\n\nWorld")

        // 验证序列化结果包含必要的内容
        XCTAssertTrue(result.contains("---"))
        XCTAssertTrue(result.contains("test-skill"))
        XCTAssertTrue(result.contains("# Hello"))
        XCTAssertTrue(result.contains("World"))
    }

    // MARK: - 往返测试（Round-trip）

    /// 测试：解析 → 序列化 → 再解析，数据应该一致
    func testRoundTrip() throws {
        let original = """
        ---
        name: round-trip
        description: Testing round trip
        license: MIT
        ---

        # Original Content
        """

        let parsed = try SkillMDParser.parse(content: original)
        let serialized = try SkillMDParser.serialize(
            metadata: parsed.metadata,
            markdownBody: parsed.markdownBody
        )
        let reparsed = try SkillMDParser.parse(content: serialized)

        XCTAssertEqual(parsed.metadata.name, reparsed.metadata.name)
        XCTAssertEqual(parsed.metadata.description, reparsed.metadata.description)
        XCTAssertTrue(reparsed.markdownBody.contains("# Original Content"))
    }
}
