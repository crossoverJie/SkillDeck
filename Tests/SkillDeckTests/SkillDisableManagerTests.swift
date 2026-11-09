import XCTest
@testable import SkillDeck

/// Pure-filesystem unit tests for `SkillDisableManager`.
///
/// These tests touch only UUID-named directories inside `FileManager.default.temporaryDirectory`,
/// so they never pollute the user's real `~/.agents/skills/` or any Agent directory. The manager's
/// path/classification helpers are pure (they only compare URL paths), so admission checks can be
/// exercised with synthetic `Skill` structs without creating those directories on disk.
final class SkillDisableManagerTests: XCTestCase {

    private let fm = FileManager.default
    private var tempRoot: URL!
    private var skillDir: URL!

    private let originalContent = "---\nname: Disable Test\ndescription: marker body\n---\n\n# Body\nhello"

    private var skillMD: URL { SkillDisableManager.skillMDURL(for: skillDir) }
    private var marker: URL { SkillDisableManager.markerURL(for: skillDir) }

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = fm.temporaryDirectory
            .appendingPathComponent("SkillDeckDisableManagerTests-\(UUID().uuidString)")
        skillDir = tempRoot.appendingPathComponent("skill-\(UUID().uuidString)")
        try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try originalContent.write(to: skillMD, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        if let tempRoot { try? fm.removeItem(at: tempRoot) }
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeSkill(
        scope: SkillScope = .sharedGlobal,
        canonicalURL: URL,
        installations: [SkillInstallation] = []
    ) -> Skill {
        Skill(
            id: canonicalURL.lastPathComponent,
            canonicalURL: canonicalURL,
            metadata: SkillMetadata(name: "Test", description: ""),
            markdownBody: "",
            scope: scope,
            installations: installations
        )
    }

    /// Assert that `expression` throws a specific `DisableError` case.
    private func assertDisableError(
        _ expectedMatch: (SkillDisableManager.DisableError) -> Bool,
        _ expression: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard let disableError = error as? SkillDisableManager.DisableError else {
                return XCTFail("Expected DisableError, got \(error)", file: file, line: line)
            }
            XCTAssertTrue(expectedMatch(disableError), "Unexpected case: \(disableError)", file: file, line: line)
        }
    }

    // MARK: - Atomic state change

    func testDisableEnableRoundTripPreservesBytes() throws {
        try SkillDisableManager.setDisabled(true, at: skillDir)

        XCTAssertFalse(fm.fileExists(atPath: skillMD.path), "SKILL.md should be renamed away")
        XCTAssertTrue(fm.fileExists(atPath: marker.path), "marker should hold the content")
        XCTAssertEqual(try Data(contentsOf: marker), Data(originalContent.utf8),
                       "disabled content must be byte-identical")

        try SkillDisableManager.setDisabled(false, at: skillDir)

        XCTAssertTrue(fm.fileExists(atPath: skillMD.path))
        XCTAssertFalse(fm.fileExists(atPath: marker.path))
        XCTAssertEqual(try Data(contentsOf: skillMD), Data(originalContent.utf8),
                       "re-enabled content must be byte-identical")
    }

    func testDisableIsIdempotent() throws {
        try SkillDisableManager.setDisabled(true, at: skillDir)
        XCTAssertNoThrow(try SkillDisableManager.setDisabled(true, at: skillDir),
                         "re-disabling an already-disabled skill must be a no-op")
        XCTAssertTrue(fm.fileExists(atPath: marker.path))
        XCTAssertFalse(fm.fileExists(atPath: skillMD.path))
    }

    func testEnableIsIdempotentWhenAlreadyActive() throws {
        XCTAssertNoThrow(try SkillDisableManager.setDisabled(false, at: skillDir),
                         "enabling an active skill must be a no-op")
        XCTAssertTrue(fm.fileExists(atPath: skillMD.path))
        XCTAssertFalse(fm.fileExists(atPath: marker.path))
        XCTAssertEqual(try Data(contentsOf: skillMD), Data(originalContent.utf8))
    }

    func testBothFilesPresentThrowsConflictInBothDirections() throws {
        // Simulate external tampering: both content files exist.
        try originalContent.write(to: marker, atomically: true, encoding: .utf8)

        assertDisableError({ if case .conflict = $0 { return true } else { return false } }) {
            try SkillDisableManager.setDisabled(true, at: self.skillDir)
        }
        assertDisableError({ if case .conflict = $0 { return true } else { return false } }) {
            try SkillDisableManager.setDisabled(false, at: self.skillDir)
        }
        // Neither file is modified.
        XCTAssertEqual(try Data(contentsOf: marker), Data(originalContent.utf8))
    }

    func testNeitherFilePresentThrowsSkillIsBrokenInBothDirections() throws {
        let emptyDir = tempRoot.appendingPathComponent("empty-\(UUID().uuidString)")
        try fm.createDirectory(at: emptyDir, withIntermediateDirectories: true)

        assertDisableError({ if case .skillIsBroken = $0 { return true } else { return false } }) {
            try SkillDisableManager.setDisabled(true, at: emptyDir)
        }
        assertDisableError({ if case .skillIsBroken = $0 { return true } else { return false } }) {
            try SkillDisableManager.setDisabled(false, at: emptyDir)
        }
    }

    // MARK: - Path helpers

    func testSkillContentURLPriority() throws {
        // Active: real SKILL.md wins.
        XCTAssertEqual(SkillDisableManager.skillContentURL(for: skillDir), skillMD)

        // Disabled: marker is returned.
        try SkillDisableManager.setDisabled(true, at: skillDir)
        XCTAssertEqual(SkillDisableManager.skillContentURL(for: skillDir), marker)

        // Both present: real SKILL.md still wins (priority).
        try originalContent.write(to: skillMD, atomically: true, encoding: .utf8)
        XCTAssertEqual(SkillDisableManager.skillContentURL(for: skillDir), skillMD)

        // Neither present: nil.
        let emptyDir = tempRoot.appendingPathComponent("empty-\(UUID().uuidString)")
        try fm.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        XCTAssertNil(SkillDisableManager.skillContentURL(for: emptyDir))
    }

    func testIsDisabledAt() throws {
        XCTAssertFalse(SkillDisableManager.isDisabled(at: skillDir), "active skill is not disabled")

        try SkillDisableManager.setDisabled(true, at: skillDir)
        XCTAssertTrue(SkillDisableManager.isDisabled(at: skillDir), "marker-only is disabled")

        // Both present (conflict state) is NOT reported as disabled.
        try originalContent.write(to: skillMD, atomically: true, encoding: .utf8)
        XCTAssertFalse(SkillDisableManager.isDisabled(at: skillDir))

        // Neither present (broken) is NOT disabled — a reinstall must be allowed.
        let emptyDir = tempRoot.appendingPathComponent("empty-\(UUID().uuidString)")
        try fm.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        XCTAssertFalse(SkillDisableManager.isDisabled(at: emptyDir))
    }

    // MARK: - Location classification

    func testClassifyLocationThreeCases() {
        let canonical = AgentType.sharedSkillsDirectoryURL.appendingPathComponent("x")
        if case .canonicalShared = SkillDisableManager.classifyLocation(canonical) {
            // expected
        } else {
            XCTFail("shared directory should classify as .canonicalShared")
        }

        let agentDir = AgentType.claudeCode.skillsDirectoryURL.appendingPathComponent("x")
        if case .agentDirectory(let agent) = SkillDisableManager.classifyLocation(agentDir) {
            XCTAssertEqual(agent, .claudeCode)
        } else {
            XCTFail("claude directory should classify as .agentDirectory(.claudeCode)")
        }

        if case .external = SkillDisableManager.classifyLocation(skillDir) {
            // expected
        } else {
            XCTFail("temporary directory should classify as .external")
        }
    }

    // MARK: - Admission

    func testCanDisableAcceptsCanonicalSharedSkill() {
        let url = AgentType.sharedSkillsDirectoryURL.appendingPathComponent("canonical-\(UUID().uuidString)")
        XCTAssertTrue(SkillDisableManager.canDisable(makeSkill(canonicalURL: url)))
    }

    func testCanDisableRejectsAgentDirectorySkillWhoseScopeWasUpgraded() {
        // `scanAll()` upgrades a real agent-directory skill with multiple inheritors to
        // `.sharedGlobal`. It must still be rejected: renaming it would not hide it from ALL
        // agents and would write into another agent's directory.
        let url = AgentType.claudeCode.skillsDirectoryURL.appendingPathComponent("upgraded-\(UUID().uuidString)")
        let skill = makeSkill(scope: .sharedGlobal, canonicalURL: url)
        XCTAssertFalse(SkillDisableManager.canDisable(skill))
    }

    func testCanDisableRejectsExternalSymlinkTarget() {
        // An external symlink target resolves to a parent that is neither canonical nor an
        // agent directory, so the same canonical-parent check rejects it as `.external`.
        XCTAssertFalse(SkillDisableManager.canDisable(makeSkill(canonicalURL: skillDir)))
    }

    func testCanDisableRejectsAgentLocalScope() {
        let url = AgentType.sharedSkillsDirectoryURL.appendingPathComponent("local-\(UUID().uuidString)")
        let skill = makeSkill(scope: .agentLocal(.claudeCode), canonicalURL: url)
        XCTAssertFalse(SkillDisableManager.canDisable(skill))
    }

    func testHasRealDuplicateRejectsCanonicalSkill() {
        let url = AgentType.sharedSkillsDirectoryURL.appendingPathComponent("dup-\(UUID().uuidString)")
        // A real, non-symlink, non-inherited copy inside an agent's own directory.
        let realCopy = SkillInstallation(
            agentType: .claudeCode,
            path: AgentType.claudeCode.skillsDirectoryURL.appendingPathComponent("dup"),
            isSymlink: false,
            isInherited: false
        )
        let skill = makeSkill(canonicalURL: url, installations: [realCopy])
        XCTAssertTrue(SkillDisableManager.hasRealDuplicate(skill), "real copy must be detected")
        XCTAssertFalse(SkillDisableManager.canDisable(skill), "fake global disable must be refused")
    }

    func testSymlinkAndInheritedInstallationsAreNotRealDuplicates() {
        let url = AgentType.sharedSkillsDirectoryURL.appendingPathComponent("links-\(UUID().uuidString)")
        let installations = [
            SkillInstallation(agentType: .claudeCode, path: url, isSymlink: true, isInherited: false),
            // Native-reading agents produce isSymlink:false + isInherited:true entries; the
            // `!isSymlink && !isInherited` combination must NOT mistake them for real copies.
            SkillInstallation(agentType: .codex, path: url, isSymlink: false, isInherited: true),
        ]
        let skill = makeSkill(canonicalURL: url, installations: installations)
        XCTAssertFalse(SkillDisableManager.hasRealDuplicate(skill))
        XCTAssertTrue(SkillDisableManager.canDisable(skill))
    }

    // MARK: - Direction-aware admission (P1 regression)

    func testCanEnableIgnoresDuplicateAndScopeChecks() {
        let url = AgentType.sharedSkillsDirectoryURL.appendingPathComponent("enable-\(UUID().uuidString)")
        let realCopy = SkillInstallation(
            agentType: .claudeCode,
            path: AgentType.claudeCode.skillsDirectoryURL.appendingPathComponent("dup"),
            isSymlink: false,
            isInherited: false
        )
        var disabled = makeSkill(scope: .sharedGlobal, canonicalURL: url, installations: [realCopy])
        disabled.isDisabled = true

        // A real duplicate correctly blocks DISABLING, but must NOT block ENABLING: renaming the
        // marker back inside the canonical store cannot affect the duplicate copy.
        XCTAssertFalse(SkillDisableManager.canDisable(disabled))
        XCTAssertTrue(SkillDisableManager.canEnable(disabled))
        XCTAssertTrue(SkillDisableManager.canToggle(disabled),
                      "the toggle must stay available while the skill is disabled")

        // `canEnable` deliberately ignores scope too — a skill that was disabled while global is
        // still recoverable even if its scope changed underneath us.
        var agentLocal = disabled
        agentLocal.scope = .agentLocal(.claudeCode)
        XCTAssertTrue(SkillDisableManager.canEnable(agentLocal))
    }

    func testCanToggleFollowsCanDisableForActiveSkills() {
        let url = AgentType.sharedSkillsDirectoryURL.appendingPathComponent("active-\(UUID().uuidString)")
        let realCopy = SkillInstallation(
            agentType: .claudeCode,
            path: url,
            isSymlink: false,
            isInherited: false
        )
        let active = makeSkill(canonicalURL: url, installations: [realCopy])
        XCTAssertFalse(active.isDisabled)
        XCTAssertFalse(SkillDisableManager.canDisable(active))
        XCTAssertFalse(SkillDisableManager.canToggle(active),
                       "an ACTIVE skill with a duplicate must still be refused")
    }

    func testCanEnableStillRequiresCanonicalParent() {
        // Enabling outside the canonical store is meaningless and unsafe.
        XCTAssertFalse(SkillDisableManager.canEnable(makeSkill(canonicalURL: skillDir)))
        let agentDir = makeSkill(
            scope: .sharedGlobal,
            canonicalURL: AgentType.claudeCode.skillsDirectoryURL.appendingPathComponent("x")
        )
        XCTAssertFalse(SkillDisableManager.canEnable(agentDir))
    }

    // MARK: - Localized error descriptions

    func testParameterizedErrorDescriptionsIncludeTheirArguments() {
        let external = SkillDisableManager.DisableError.externalLocation(skillDir)
        XCTAssertTrue(external.errorDescription?.contains(skillDir.path) == true,
                      "externalLocation must interpolate the path via String(format:)")
        XCTAssertNotEqual(external.errorDescription, L10nKeys.skillDisableErrorExternalLocation)

        let duplicate = SkillDisableManager.DisableError.duplicateRealCopy(.claudeCode)
        XCTAssertTrue(duplicate.errorDescription?.contains(AgentType.claudeCode.displayName) == true,
                      "duplicateRealCopy must interpolate the agent display name")
    }

    func testAllErrorCasesProduceNonEmptyLocalizedDescriptions() {
        let cases: [SkillDisableManager.DisableError] = [
            .conflict, .skillIsBroken, .unsupportedScope,
            .externalLocation(skillDir), .agentDirectoryLocation(.claudeCode),
            .duplicateRealCopy(.claudeCode), .skillIsDisabled, .installOnDisabled,
            .brokenNeedsManualReinstall,
        ]
        for errorCase in cases {
            XCTAssertNotNil(errorCase.errorDescription, "\(errorCase) needs a description")
            XCTAssertFalse(errorCase.errorDescription?.isEmpty ?? true, "\(errorCase) description is empty")
        }
    }
}
