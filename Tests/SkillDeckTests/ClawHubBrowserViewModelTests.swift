import XCTest
@testable import SkillDeck

/// Unit tests for ClawHubBrowserViewModel's installed-state matching rules.
///
/// The ClawHub flow stores `sourceType = "clawhub"` and uses the marketplace slug as `source`, so
/// the ViewModel should prefer slug-aware matching instead of generic skill-name heuristics.
@MainActor
final class ClawHubBrowserViewModelTests: XCTestCase {

    private func makeSkill(id: String, source: String? = nil, sourceType: String = "clawhub") -> Skill {
        let lockEntry: LockEntry? = source.map { src in
            LockEntry(
                source: src,
                sourceType: sourceType,
                sourceUrl: "https://clawhub.ai/skills/\(src)",
                skillPath: "\(id)/SKILL.md",
                skillFolderHash: "",
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

    private func makeClawHubSkill(slug: String) -> ClawHubSkill {
        ClawHubSkill(
            slug: slug,
            displayName: slug,
            summary: "",
            latestVersion: "1.0.0",
            downloads: 10,
            stars: 2,
            versionCount: 1,
            ownerHandle: "skills",
            ownerDisplayName: nil,
            updatedAtMilliseconds: nil
        )
    }

    func testIsInstalledReturnsTrueWhenClawHubSourceMatchesSlug() {
        let skillManager = SkillManager()
        skillManager.skills = [makeSkill(id: "browser-use", source: "browser-use")]

        let viewModel = ClawHubBrowserViewModel(skillManager: skillManager)
        viewModel.syncInstalledSkills()

        XCTAssertTrue(viewModel.isInstalled(makeClawHubSkill(slug: "browser-use")))
    }

    func testIsInstalledReturnsFalseWhenClawHubSourceDiffers() {
        let skillManager = SkillManager()
        skillManager.skills = [makeSkill(id: "browser-use", source: "other-skill")]

        let viewModel = ClawHubBrowserViewModel(skillManager: skillManager)
        viewModel.syncInstalledSkills()

        XCTAssertFalse(viewModel.isInstalled(makeClawHubSkill(slug: "browser-use")))
    }

    func testIsInstalledFallsBackToSkillIDForManualInstall() {
        let skillManager = SkillManager()
        skillManager.skills = [makeSkill(id: "browser-use", source: nil)]

        let viewModel = ClawHubBrowserViewModel(skillManager: skillManager)
        viewModel.syncInstalledSkills()

        XCTAssertTrue(viewModel.isInstalled(makeClawHubSkill(slug: "browser-use")))
    }
}
