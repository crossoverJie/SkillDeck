import XCTest
@testable import SkillDeck

/// Integration tests for the scanner's disabled / broken / ghost-row handling.
///
/// These tests intentionally write to the REAL `~/.agents/skills/` directory, because
/// `SkillScanner.scanAll()` discovers skills there (and in every Agent directory) and there is no
/// injected scanner seam. Isolation rules (mirroring the plan):
///  - setUp creates the shared directory if it is missing (only skipping when it truly cannot be
///    created), so the whole suite is NOT silently skipped on a clean CI runner.
///  - Every directory / symlink we create is prefixed with this test instance's UUID.
///  - tearDown removes ONLY those UUID-prefixed entries; it never touches the real
///    `~/.agents/.skill-lock.json` or any non-prefixed skill.
final class SkillScannerDisableTests: XCTestCase {

    private let fm = FileManager.default
    private var uuid: String!
    private var createdSharedSkillsDir = false
    /// Every path this test created, removed verbatim in tearDown.
    private var managedPaths: [URL] = []

    private var shared: URL { SkillScanner.sharedSkillsURL }

    override func setUp() async throws {
        try await super.setUp()
        uuid = UUID().uuidString

        if !fm.fileExists(atPath: shared.path) {
            do {
                try fm.createDirectory(at: shared, withIntermediateDirectories: true)
                createdSharedSkillsDir = true
            } catch {
                try XCTSkip("Cannot create shared skills directory: \(error)")
            }
        }
        // Only skip when the directory genuinely cannot be created / is not writable. Do NOT
        // `XCTSkipUnless` on existence alone — that would skip the whole suite on CI.
        try XCTSkipUnless(fm.isWritableFile(atPath: shared.path),
                          "shared skills directory is not writable")
        print("[SkillScannerDisableTests] sharedSkillsURL ready")
    }

    override func tearDown() async throws {
        for url in managedPaths {
            try? fm.removeItem(at: url)
        }
        // Defensive: remove any UUID-prefixed symlink left in an Agent directory.
        for agent in AgentType.allCases {
            let link = agent.skillsDirectoryURL.appendingPathComponent(uuid)
            if SymlinkManager.isSymlink(at: link) {
                try? fm.removeItem(at: link)
            }
        }
        // Only remove the shared directory itself if WE created it and it is now empty.
        if createdSharedSkillsDir,
           let contents = try? fm.contentsOfDirectory(atPath: shared.path),
           contents.isEmpty {
            try? fm.removeItem(at: shared)
        }
        try await super.tearDown()
    }

    // MARK: - Helpers

    private let skillContent = "---\nname: Marker Name\ndescription: from marker\n---\n\n# Body\nmarker-content"

    @discardableResult
    private func makeSkillDir(_ suffix: String, content: String? = nil) throws -> URL {
        let name = "\(uuid!)-\(suffix)"
        let dir = shared.appendingPathComponent(name)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        managedPaths.append(dir)
        if let content {
            try content.write(to: SkillDisableManager.skillMDURL(for: dir),
                              atomically: true, encoding: .utf8)
        }
        return dir
    }

    private func linkToClaude(_ dir: URL) throws {
        try SymlinkManager.createSymlink(from: dir, to: .claudeCode)
        managedPaths.append(
            AgentType.claudeCode.skillsDirectoryURL.appendingPathComponent(dir.lastPathComponent)
        )
    }

    private func scan() async throws -> [Skill] {
        try await SkillScanner().scanAll()
    }

    private func find(_ suffix: String, in skills: [Skill]) -> Skill? {
        skills.first { $0.id == "\(uuid!)-\(suffix)" }
    }

    // MARK: - (a) Disabled skill keeps metadata/body and all installations

    func testDisabledSkillParsesMarkerAndKeepsInstallations() async throws {
        let dir = try makeSkillDir("a", content: skillContent)
        try linkToClaude(dir)
        try SkillDisableManager.setDisabled(true, at: dir)

        let skills = try await scan()
        let skill = try XCTUnwrap(find("a", in: skills))
        XCTAssertTrue(skill.isDisabled)
        XCTAssertFalse(skill.isBroken)
        XCTAssertEqual(skill.metadata.name, "Marker Name", "name must come from the marker")
        XCTAssertTrue(skill.markdownBody.contains("marker-content"), "body must come from the marker")

        XCTAssertTrue(skill.installations.contains { $0.agentType == .claudeCode },
                      "direct symlink assignment must be preserved")
        for agent in [AgentType.codex, .openCode, .qoder, .pi] {
            XCTAssertTrue(skill.installations.contains { $0.agentType == agent },
                          "\(agent.displayName) native shared-directory entry must be preserved")
        }
    }

    // MARK: - (b) Native-reading agents see nothing while disabled

    func testDisabledSkillHasNoSkillMDForNativeReaders() async throws {
        let dir = try makeSkillDir("b", content: skillContent)
        try SkillDisableManager.setDisabled(true, at: dir)

        XCTAssertFalse(fm.fileExists(atPath: SkillDisableManager.skillMDURL(for: dir).path))
        XCTAssertTrue(fm.fileExists(atPath: SkillDisableManager.markerURL(for: dir).path))
        // Codex/OpenCode/Qoder/Pi read ~/.agents/skills/ directly; with no SKILL.md there is
        // nothing for them to load. The scanner still surfaces the row as disabled (not vanished).
        let skills = try await scan()
        let skill = try XCTUnwrap(find("b", in: skills))
        XCTAssertTrue(skill.isDisabled)
    }

    // MARK: - (c) State is self-describing and survives a fresh scanner ("restart")

    func testFreshScannerStillReportsDisabledState() async throws {
        let dir = try makeSkillDir("c", content: skillContent)
        try SkillDisableManager.setDisabled(true, at: dir)

        let firstScan = try await scan()
        XCTAssertTrue(find("c", in: firstScan)?.isDisabled == true)
        // A brand-new scanner instance re-derives the state purely from disk: no UserDefaults,
        // no JSON store, no in-memory flag.
        let secondScan = try await scan()
        XCTAssertTrue(find("c", in: secondScan)?.isDisabled == true)
    }

    // MARK: - (d) Re-enable restores active state without touching symlinks

    func testEnableRestoresActiveAndKeepsSymlink() async throws {
        let dir = try makeSkillDir("d", content: skillContent)
        try linkToClaude(dir)
        let link = AgentType.claudeCode.skillsDirectoryURL
            .appendingPathComponent(dir.lastPathComponent)

        try SkillDisableManager.setDisabled(true, at: dir)
        try SkillDisableManager.setDisabled(false, at: dir)

        let skills = try await scan()
        let skill = try XCTUnwrap(find("d", in: skills))
        XCTAssertFalse(skill.isDisabled)
        XCTAssertFalse(skill.isBroken)
        XCTAssertEqual(skill.metadata.name, "Marker Name")
        XCTAssertTrue(SymlinkManager.isSymlink(at: link),
                      "re-enable must not recreate or remove the assignment symlink")
    }

    // MARK: - (e) Deleted marker produces a visible broken row (not silently dropped)

    func testDeletedMarkerProducesBrokenSkill() async throws {
        let dir = try makeSkillDir("e", content: skillContent)
        try linkToClaude(dir)  // direct install so the row is unambiguously meaningful
        try SkillDisableManager.setDisabled(true, at: dir)
        try fm.removeItem(at: SkillDisableManager.markerURL(for: dir))

        let skills = try await scan()
        let skill = try XCTUnwrap(find("e", in: skills),
                                  "broken skill must stay visible for delete / reinstall")
        XCTAssertTrue(skill.isBroken)
        XCTAssertFalse(skill.isDisabled)
    }

    // MARK: - (f) Unrelated agent-directory subfolder does not become a ghost row

    func testAgentDirectoryUnrelatedSubfolderProducesNoGhostRow() async throws {
        let agentDir = AgentType.claudeCode.skillsDirectoryURL
        try fm.createDirectory(at: agentDir, withIntermediateDirectories: true)
        let ghost = agentDir.appendingPathComponent("\(uuid!)-ghost")
        try fm.createDirectory(at: ghost, withIntermediateDirectories: true)
        managedPaths.append(ghost)

        // No SKILL.md / marker, and the agent-directory pass has `.agentLocal` scope, so the
        // broken branch (global pass only) must not fire.
        let skills = try await scan()
        XCTAssertNil(find("ghost", in: skills))
    }

    // MARK: - (g) Dangling symlink does not become a broken row

    func testDanglingSymlinkProducesNoBrokenRow() async throws {
        let name = "\(uuid!)-dangling"
        let link = shared.appendingPathComponent(name)
        let missingDestination = fm.temporaryDirectory
            .appendingPathComponent("SkillDeckDangling-\(uuid!)-missing")
        try fm.createSymbolicLink(at: link, withDestinationURL: missingDestination)
        managedPaths.append(link)

        // `fileExists(atPath:isDirectory:)` returns false for a dangling symlink, so the broken
        // branch returns nil instead of producing a row for a nonexistent canonicalURL.
        let skills = try await scan()
        XCTAssertNil(skills.first { $0.id == name })
    }
}
