import XCTest
@testable import SkillDeck

/// Unit tests for AgentType enum
///
/// Verifies that each agent's computed properties return the expected values.
/// Swift enums are exhaustively checked by the compiler, so adding a new case
/// without updating all switch statements will cause a compile error — but these
/// tests provide additional runtime validation of the property values themselves.
final class AgentTypeTests: XCTestCase {

    // MARK: - Antigravity Agent Properties

    /// Verify all computed properties of the Antigravity agent type
    func testAntigravityProperties() {
        let agent = AgentType.antigravity

        // rawValue is used as the Codable key in lock file JSON
        XCTAssertEqual(agent.rawValue, "antigravity")
        XCTAssertEqual(agent.displayName, "Antigravity")
        XCTAssertEqual(agent.detectCommand, "antigravity")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.gemini/antigravity/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.gemini/antigravity")
        XCTAssertEqual(agent.iconName, "arrow.up.circle")
        XCTAssertEqual(agent.brandColor, "indigo")

        // Antigravity does not read other agents' directories
        XCTAssertTrue(agent.additionalReadableSkillsDirectories.isEmpty)
    }

    // MARK: - Cursor Agent Properties

    /// Verify all computed properties of the Cursor agent type
    func testCursorProperties() {
        let agent = AgentType.cursor

        // rawValue is used as the Codable key in lock file JSON
        XCTAssertEqual(agent.rawValue, "cursor")
        XCTAssertEqual(agent.displayName, "Cursor")
        XCTAssertEqual(agent.detectCommand, "cursor")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.cursor/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.cursor")
        XCTAssertEqual(agent.iconName, "cursorarrow.rays")
        XCTAssertEqual(agent.brandColor, "cyan")

        // Cursor reads Claude Code's skills directory as an additional source
        let additionalDirs = agent.additionalReadableSkillsDirectories
        XCTAssertEqual(additionalDirs.count, 1)
        XCTAssertEqual(additionalDirs[0].sourceAgent, .claudeCode)
    }

    // MARK: - CaseIterable Count

    /// Verify the total number of supported agents
    /// This test catches accidental removal of agent cases
    func testAllCasesCount() {
        // 7 agents: claudeCode, codex, geminiCLI, copilotCLI, openCode, antigravity, cursor
        XCTAssertEqual(AgentType.allCases.count, 7)
    }
}
