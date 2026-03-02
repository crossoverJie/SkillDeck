import XCTest
@testable import SkillDeck

/// Unit tests for RegistryBrowserViewModel's source-aware "Installed" badge matching.
///
/// These tests verify the fix for the bug where registry skills with the same skillId
/// but from different repositories were all incorrectly showing as "Installed".
/// The fix makes `isInstalled()` check both skillId AND source repo.
///
/// XCTest is Swift's built-in testing framework (similar to JUnit / Go's testing package).
/// @MainActor is required because RegistryBrowserViewModel and SkillManager are @MainActor-isolated.
@MainActor
final class RegistryBrowserViewModelTests: XCTestCase {

    // MARK: - Helpers

    /// Create a minimal Skill model for testing.
    ///
    /// Builds a Skill struct with just enough fields to drive the ViewModel's
    /// `syncInstalledSkills()` logic (id and optional lockEntry).
    /// - Parameters:
    ///   - id: The skill directory name (e.g., "ui-ux-pro-max")
    ///   - source: Optional source repo in "owner/repo" format. When provided, a LockEntry is attached.
    /// - Returns: A Skill instance suitable for testing
    private func makeSkill(id: String, source: String? = nil) -> Skill {
        // Build a lock entry only if source is provided.
        // Skills without a lock entry represent manual installs (not from registry).
        let lockEntry: LockEntry? = source.map { src in
            LockEntry(
                source: src,
                sourceType: "github",
                sourceUrl: "https://github.com/\(src).git",
                skillPath: "skills/\(id)/SKILL.md",
                skillFolderHash: "abc123",
                installedAt: "2025-01-01T00:00:00Z",
                updatedAt: "2025-01-01T00:00:00Z"
            )
        }

        return Skill(
            id: id,
            canonicalURL: URL(fileURLWithPath: "/tmp/skills/\(id)"),
            metadata: SkillMetadata(name: id, description: ""),
            markdownBody: "",
            scope: .sharedGlobal,
            installations: [],
            lockEntry: lockEntry
        )
    }

    /// Create a minimal RegistrySkill for testing.
    ///
    /// RegistrySkill represents a skill from the skills.sh registry.
    /// - Parameters:
    ///   - skillId: The skill directory name (e.g., "ui-ux-pro-max")
    ///   - source: The repository in "owner/repo" format (e.g., "nextlevelbuilder/ui-ux-pro-max-skill")
    /// - Returns: A RegistrySkill instance suitable for testing
    private func makeRegistrySkill(skillId: String, source: String) -> RegistrySkill {
        RegistrySkill(
            id: "\(source)/\(skillId)",
            skillId: skillId,
            name: skillId,
            installs: 100,
            source: source,
            installsYesterday: nil,
            change: nil
        )
    }

    // MARK: - isInstalled Tests

    /// Test: isInstalled returns true when both skillId AND source match the installed skill.
    ///
    /// This is the happy path — user installed "ui-ux-pro-max" from "alice/skills",
    /// and the registry shows the same skill from the same repo.
    func testIsInstalledReturnsTrueWhenSourceMatches() {
        let skillManager = SkillManager()
        // Simulate a locally installed skill with a lock entry recording its source repo
        skillManager.skills = [makeSkill(id: "ui-ux-pro-max", source: "alice/skills")]

        let vm = RegistryBrowserViewModel(skillManager: skillManager)
        vm.syncInstalledSkills()

        // Registry skill from the SAME repo should be marked as installed
        let registrySkill = makeRegistrySkill(skillId: "ui-ux-pro-max", source: "alice/skills")
        XCTAssertTrue(vm.isInstalled(registrySkill), "Should be installed when skillId and source both match")
    }

    /// Test: isInstalled returns false when skillId matches but source differs.
    ///
    /// This is the bug fix scenario — user installed "ui-ux-pro-max" from "alice/skills",
    /// but the registry also shows a DIFFERENT "ui-ux-pro-max" from "bob/other-skills".
    /// Before the fix, both would show as "Installed" (wrong). After the fix, only the matching source shows it.
    func testIsInstalledReturnsFalseWhenSourceDiffers() {
        let skillManager = SkillManager()
        // Locally installed from "alice/skills"
        skillManager.skills = [makeSkill(id: "ui-ux-pro-max", source: "alice/skills")]

        let vm = RegistryBrowserViewModel(skillManager: skillManager)
        vm.syncInstalledSkills()

        // Registry skill from a DIFFERENT repo should NOT be marked as installed
        let registrySkill = makeRegistrySkill(skillId: "ui-ux-pro-max", source: "bob/other-skills")
        XCTAssertFalse(vm.isInstalled(registrySkill), "Should NOT be installed when source differs even if skillId matches")
    }

    /// Test: isInstalled returns true for manually installed skills (no lock entry) via ID-only fallback.
    ///
    /// Skills installed manually (e.g., by copying files) don't have a lock entry,
    /// so there's no source to compare. In this case, we fall back to skillId-only matching
    /// for backward compatibility — the skill directory name is enough.
    func testIsInstalledFallbackForSkillWithoutLockEntry() {
        let skillManager = SkillManager()
        // Manually installed skill — no lock entry, so no source info
        skillManager.skills = [makeSkill(id: "my-custom-skill")]

        let vm = RegistryBrowserViewModel(skillManager: skillManager)
        vm.syncInstalledSkills()

        // Any registry skill with matching skillId should be marked as installed (fallback behavior)
        let registrySkill = makeRegistrySkill(skillId: "my-custom-skill", source: "anyone/any-repo")
        XCTAssertTrue(vm.isInstalled(registrySkill), "Should be installed via ID-only fallback when no lock entry exists")
    }

    /// Test: isInstalled returns false for a completely uninstalled skill.
    ///
    /// Verifies baseline behavior — a skill that isn't installed locally at all
    /// should never show as "Installed" regardless of its registry source.
    func testIsInstalledReturnsFalseForUninstalledSkill() {
        let skillManager = SkillManager()
        // Install a different skill
        skillManager.skills = [makeSkill(id: "some-other-skill", source: "alice/skills")]

        let vm = RegistryBrowserViewModel(skillManager: skillManager)
        vm.syncInstalledSkills()

        // Registry skill with a completely different skillId should not be installed
        let registrySkill = makeRegistrySkill(skillId: "ui-ux-pro-max", source: "alice/skills")
        XCTAssertFalse(vm.isInstalled(registrySkill), "Should NOT be installed when skillId doesn't match any local skill")
    }
}
