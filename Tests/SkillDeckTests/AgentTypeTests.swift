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

    // MARK: - Codex Agent Properties

    /// Verify all computed properties of the Codex agent type
    /// Codex now has its own skills directory (~/.codex/skills/) instead of sharing ~/.agents/skills/
    func testCodexProperties() {
        let agent = AgentType.codex

        XCTAssertEqual(agent.rawValue, "codex")
        XCTAssertEqual(agent.displayName, "Codex")
        XCTAssertEqual(agent.detectCommand, "codex")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.codex/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.codex")
        XCTAssertEqual(agent.iconName, "terminal")
        XCTAssertEqual(agent.brandColor, "green")

        // Codex also reads the shared canonical directory ~/.agents/skills/
        let additionalDirs = agent.additionalReadableSkillsDirectories
        XCTAssertEqual(additionalDirs.count, 1)
        XCTAssertNil(additionalDirs[0].sourceAgent)
        XCTAssertTrue(agent.readsSharedCanonicalDirectory)
    }

    // MARK: - Kiro Agent Properties

    /// Verify all computed properties of the Kiro agent type
    func testKiroProperties() {
        let agent = AgentType.kiro

        // rawValue is used as the Codable key in lock file JSON
        XCTAssertEqual(agent.rawValue, "kiro")
        XCTAssertEqual(agent.displayName, "Kiro")
        XCTAssertEqual(agent.detectCommand, "kiro")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.kiro/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.kiro")
        XCTAssertEqual(agent.iconName, "k.circle")
        XCTAssertEqual(agent.brandColor, "violet")

        // Kiro does not read other agents' directories
        XCTAssertTrue(agent.additionalReadableSkillsDirectories.isEmpty)
    }

    // MARK: - CodeBuddy Agent Properties

    /// Verify all computed properties of the CodeBuddy agent type
    func testCodeBuddyProperties() {
        let agent = AgentType.codeBuddy

        // rawValue is used as the Codable key in lock file JSON
        XCTAssertEqual(agent.rawValue, "codebuddy")
        XCTAssertEqual(agent.displayName, "CodeBuddy")
        XCTAssertEqual(agent.detectCommand, "codebuddy")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.codebuddy/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.codebuddy")
        XCTAssertEqual(agent.iconName, "c.circle")
        XCTAssertEqual(agent.brandColor, "pink")

        // CodeBuddy does not read other agents' directories
        XCTAssertTrue(agent.additionalReadableSkillsDirectories.isEmpty)
    }

    // MARK: - OpenClaw Agent Properties

    /// Verify all computed properties of the OpenClaw agent type
    func testOpenClawProperties() {
        let agent = AgentType.openClaw

        // rawValue is used as the Codable key in lock file JSON
        XCTAssertEqual(agent.rawValue, "openclaw")
        XCTAssertEqual(agent.displayName, "OpenClaw")
        XCTAssertEqual(agent.detectCommand, "openclaw")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.openclaw/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.openclaw")
        XCTAssertEqual(agent.iconName, "o.circle")
        XCTAssertEqual(agent.brandColor, "red")

        // OpenClaw does not read other agents' directories
        XCTAssertTrue(agent.additionalReadableSkillsDirectories.isEmpty)
    }

    // MARK: - Trae Agent Properties

    /// Verify all computed properties of the Trae agent type
    /// Trae is ByteDance's AI IDE, standalone agent with no cross-directory reading
    func testTraeProperties() {
        let agent = AgentType.trae

        // rawValue is used as the Codable key in lock file JSON
        XCTAssertEqual(agent.rawValue, "trae")
        XCTAssertEqual(agent.displayName, "Trae")
        XCTAssertEqual(agent.detectCommand, "trae")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.trae/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.trae")
        XCTAssertEqual(agent.iconName, "t.circle")
        XCTAssertEqual(agent.brandColor, "brightGreen")

        // Trae does not read other agents' directories (standalone agent)
        XCTAssertTrue(agent.additionalReadableSkillsDirectories.isEmpty)
    }

    // MARK: - Qoder Agent Properties

    /// Verify all computed properties of the Qoder agent type
    /// Qoder reads its own directory plus the shared ~/.agents/skills/ compatibility directory
    func testQoderProperties() {
        let agent = AgentType.qoder

        // rawValue is used as the Codable key in lock file JSON
        XCTAssertEqual(agent.rawValue, "qoder")
        XCTAssertEqual(agent.displayName, "Qoder")
        XCTAssertEqual(agent.detectCommand, "qoder")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.qoder/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.qoder")
        XCTAssertEqual(agent.iconName, "q.circle")
        XCTAssertEqual(agent.brandColor, "orange")

        // Qoder loads the legacy ~/.agents/skills/ compatibility directory by default
        let additionalDirs = agent.additionalReadableSkillsDirectories
        XCTAssertEqual(additionalDirs.count, 1)
        XCTAssertNil(additionalDirs[0].sourceAgent)
        XCTAssertTrue(agent.readsSharedCanonicalDirectory)
    }

    // MARK: - QClaw Agent Properties

    /// Verify all computed properties of the QClaw agent type
    /// QClaw is an AI coding assistant with standalone directory structure
    func testQClawProperties() {
        let agent = AgentType.qclaw

        // rawValue is used as the Codable key in lock file JSON
        XCTAssertEqual(agent.rawValue, "qclaw")
        XCTAssertEqual(agent.displayName, "QClaw")
        XCTAssertEqual(agent.detectCommand, "qclaw")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.qclaw/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.qclaw")
        XCTAssertEqual(agent.iconName, "hand.raised.circle")
        XCTAssertEqual(agent.brandColor, "mint")

        // QClaw does not read other agents' directories (standalone agent)
        XCTAssertTrue(agent.additionalReadableSkillsDirectories.isEmpty)
    }

    // MARK: - WorkBuddy Agent Properties

    /// Verify all computed properties of the WorkBuddy agent type
    /// WorkBuddy is an AI coding assistant with standalone directory structure
    func testWorkBuddyProperties() {
        let agent = AgentType.workbuddy

        // rawValue is used as the Codable key in lock file JSON
        XCTAssertEqual(agent.rawValue, "workbuddy")
        XCTAssertEqual(agent.displayName, "WorkBuddy")
        XCTAssertEqual(agent.detectCommand, "workbuddy")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.workbuddy/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.workbuddy")
        XCTAssertEqual(agent.iconName, "w.circle")
        XCTAssertEqual(agent.brandColor, "yellow")

        // WorkBuddy does not read other agents' directories (standalone agent)
        XCTAssertTrue(agent.additionalReadableSkillsDirectories.isEmpty)
    }

    // MARK: - Pi Agent Properties

    /// Verify all computed properties of the Pi agent type
    /// Pi keeps skills in its agent directory and natively reads the Agent Skills
    /// shared location ~/.agents/skills/, which is also SkillDeck's canonical store.
    func testPiProperties() {
        let agent = AgentType.pi

        // rawValue is used as the Codable key in lock file JSON
        XCTAssertEqual(agent.rawValue, "pi")
        XCTAssertEqual(agent.displayName, "Pi")
        XCTAssertEqual(agent.detectCommand, "pi")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.pi/agent/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.pi/agent")
        XCTAssertEqual(agent.iconName, "p.circle")
        XCTAssertEqual(agent.brandColor, "slate")

        // Pi reads the shared canonical directory natively (no per-agent symlink needed)
        let additionalDirs = agent.additionalReadableSkillsDirectories
        XCTAssertEqual(additionalDirs.count, 1)
        XCTAssertEqual(additionalDirs[0].url, AgentType.sharedSkillsDirectoryURL)
        XCTAssertNil(additionalDirs[0].sourceAgent)
        XCTAssertTrue(agent.readsSharedCanonicalDirectory)
    }

    // MARK: - Canonical Directory Matching

    /// The canonical-directory check must not depend on whether the directory currently exists.
    ///
    /// `URL ==` compares the `hasDirectoryPath` flag as well, and that flag is inferred from the
    /// filesystem by `URL(fileURLWithPath:)`. On CI `~/.agents/skills` did not exist yet, so the
    /// inferred flag differed from a `deletingLastPathComponent()` URL and the shared-directory
    /// skills were treated as inherited instead of native support.
    func testCanonicalSharedDirectoryComparisonIgnoresTrailingSlashAndExistence() {
        let shared = AgentType.sharedSkillsDirectoryURL

        // Same directory, directory-style URL (trailing slash) — the flag `deletingLastPathComponent()` produces.
        let withTrailingSlash = URL(fileURLWithPath: shared.path + "/", isDirectory: true)
        XCTAssertTrue(AgentType.isCanonicalSharedDirectory(withTrailingSlash))

        // Same directory, no trailing slash (how the constant may be built on a fresh machine).
        let withoutTrailingSlash = URL(fileURLWithPath: shared.path)
        XCTAssertTrue(AgentType.isCanonicalSharedDirectory(withoutTrailingSlash))

        // A child path's parent resolves back to the canonical directory.
        let childParent = shared
            .appendingPathComponent("demo-skill")
            .deletingLastPathComponent()
        XCTAssertTrue(AgentType.isCanonicalSharedDirectory(childParent))

        // Unrelated directories stay unrelated.
        XCTAssertFalse(AgentType.isCanonicalSharedDirectory(URL(fileURLWithPath: "/tmp/skills")))
        XCTAssertFalse(AgentType.isCanonicalSharedDirectory(shared.appendingPathComponent("demo-skill")))
    }

    /// Regression test for the CI-only failure: the compared directories must not exist, so
    /// `URL(fileURLWithPath:)` has no filesystem hint to infer `hasDirectoryPath` from.
    /// CI runs in a fresh home directory where `~/.agents/skills` is still absent.
    func testIsSameDirectoryOnMissingPathsIgnoresTrailingSlash() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))

        let plain = URL(fileURLWithPath: missing.path)
        let slashed = URL(fileURLWithPath: missing.path + "/", isDirectory: true)
        XCTAssertTrue(AgentType.isSameDirectory(plain, slashed))
        XCTAssertTrue(AgentType.isSameDirectory(slashed, plain))

        // `deletingLastPathComponent()` always produces a trailing slash; the parent of a child
        // built from the un-slashed URL must still match.
        let childParent = plain.appendingPathComponent("demo-skill").deletingLastPathComponent()
        XCTAssertTrue(AgentType.isSameDirectory(plain, childParent))

        // Real prefixes must still differ.
        XCTAssertFalse(AgentType.isSameDirectory(plain, missing.deletingLastPathComponent()))
    }

    /// Declaration order is the UI order: `allCases` feeds the sidebar, install sheets,
    /// import sheets and Agent toggles. This test makes an unintentional reorder visible.
    func testAllCasesDisplayOrder() {
        XCTAssertEqual(
            AgentType.allCases.map(\.rawValue),
            [
                "claude-code", "codex", "copilot-cli", "opencode", "pi",
                "cursor", "kiro", "codebuddy", "trae", "qoder", "qclaw", "workbuddy",
                "gemini-cli", "antigravity", "openclaw",
            ]
        )
    }

    // MARK: - CaseIterable Count

    /// Verify the total number of supported agents
    /// This test catches accidental removal of agent cases
    func testAllCasesCount() {
        // 15 agents: claudeCode, codex, geminiCLI, copilotCLI, openCode, antigravity, cursor, kiro, codeBuddy, openClaw, trae, qoder, qclaw, workbuddy, pi
        XCTAssertEqual(AgentType.allCases.count, 15)
    }
}
