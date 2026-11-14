import XCTest

@testable import SkillDeck

/// Tests for the Dashboard's "group by install source" layer.
///
/// Grouping is orthogonal to sorting: `filteredSkills` decides the order, `sourceGroups(from:)`
/// merely cuts that ordered array into sections. These tests therefore always feed a plain
/// already-ordered array in and assert on the resulting section identities / titles.
///
/// `@MainActor` on every test: `DashboardViewModel` is `@MainActor @Observable`, so instances
/// may only be created and mutated on the main actor (same pattern as `DashboardUsageSortTests`).
@MainActor
final class DashboardGroupingTests: XCTestCase {

    // MARK: - Merging / splitting groups

    func testCaseVariantsMergeIntoOneGroup() {
        let viewModel = makeViewModel()
        let skills = [
            makeSkill(id: "agent-notifier", source: "crossoverJie/skills"),
            makeSkill(id: "session-export", source: "crossoverjie/skills"),
        ]

        let groups = viewModel.sourceGroups(from: skills)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].skills.count, 2)
        // The header casing comes from the group-wide vote, not from the first member.
        XCTAssertEqual(groups[0].title, .literal("crossoverJie/skills"))
    }

    func testSimilarReposDoNotMerge() {
        // Pins that `lowercased()` alone does not over-merge: `skilldeck != skills`.
        let viewModel = makeViewModel()
        let skills = [
            makeSkill(id: "a", source: "crossoverJie/SkillDeck"),
            makeSkill(id: "b", source: "crossoverJie/skills"),
        ]

        let groups = viewModel.sourceGroups(from: skills)

        XCTAssertEqual(groups.map(\.id), ["github:crossoverjie/skilldeck", "github:crossoverjie/skills"])
    }

    func testSkillsWithoutLockEntryShareFallbackGroup() {
        let viewModel = makeViewModel()
        let skills = [
            makeSkill(id: "clipshelf"),
            makeSkill(id: "generate-wiki"),
            makeSkill(id: "starrocks-upgrade"),
        ]

        let groups = viewModel.sourceGroups(from: skills)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].id, "unknown:no-entry")
        XCTAssertEqual(groups[0].title, .localized(L10nKeys.dashboardGroupUnknownSource))
        XCTAssertNil(groups[0].helpText)
        XCTAssertEqual(groups[0].skills.count, 3)
    }

    func testClawHubSkillsShareOneGroup() {
        // Different slugs — one of them containing a slash, which is why dispatch is on
        // `sourceType` and never on `source.contains("/")`.
        let viewModel = makeViewModel()
        let skills = [
            makeSkill(id: "pdf", source: "pdf", sourceType: "clawhub"),
            makeSkill(id: "some-skill", source: "org/some-skill", sourceType: "clawhub"),
        ]

        let groups = viewModel.sourceGroups(from: skills)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].id, "marketplace:clawhub")
        XCTAssertEqual(groups[0].title, .literal("ClawHub"))
        XCTAssertEqual(groups[0].skills.count, 2)
    }

    func testLocalPathGroupUsesLastPathComponent() {
        let viewModel = makeViewModel()
        let skills = [
            makeSkill(id: "slidev", source: "/Users/x/repo-a/", sourceType: "local"),
        ]

        let groups = viewModel.sourceGroups(from: skills)

        XCTAssertEqual(groups.count, 1)
        // Trailing slash removed by `standardizedFileURL`, key lower-cased.
        XCTAssertEqual(groups[0].id, "path:/users/x/repo-a")
        XCTAssertEqual(groups[0].title, .literal("repo-a"))
        // The tooltip keeps the on-disk casing: it is meant for a human to read.
        XCTAssertEqual(groups[0].helpText, "/Users/x/repo-a")
    }

    func testEmptySourceFallsIntoFallbackGroup() {
        // Pins the `default:` catch-all: a known sourceType with a blank source must not
        // disappear, and must not produce a group with an empty header.
        let viewModel = makeViewModel()
        let skills = [makeSkill(id: "orphan", source: "   ", sourceType: "github")]

        let groups = viewModel.sourceGroups(from: skills)

        XCTAssertEqual(groups.map(\.id), ["unknown:no-entry"])
        XCTAssertEqual(groups[0].title, .localized(L10nKeys.dashboardGroupUnknownSource))
    }

    func testUnknownSourceTypeKeepsOwnGroupAndTitle() {
        // Historical / hand-edited CommitHashCache JSON can carry any `sourceType` string;
        // `SkillManager` copies it verbatim. Each such source keeps its own group so its
        // tooltip/title is not swallowed by the fallback bucket.
        let viewModel = makeViewModel()
        let skills = [makeSkill(id: "weird", source: "Some/Repo", sourceType: "weird")]

        let groups = viewModel.sourceGroups(from: skills)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].id, "unknown:some/repo")
        XCTAssertEqual(groups[0].title, .literal("Some/Repo"))
    }

    // MARK: - Ordering interaction with sortOrder / sortDirection

    func testGroupOrderFollowsSortOrder() {
        let manager = makeManager()
        let viewModel = DashboardViewModel(skillManager: manager)
        manager.skills = [
            makeSkill(id: "alpha", name: "Alpha", source: "aaa/one"),
            makeSkill(id: "zulu", name: "Zulu", source: "zzz/two"),
        ]

        // Name ascending → aaa/one ranks first, so its group comes first.
        viewModel.sortOrder = .name
        viewModel.sortDirection = .ascending
        XCTAssertEqual(
            viewModel.sourceGroups(from: viewModel.filteredSkills).map(\.id),
            ["github:aaa/one", "github:zzz/two"]
        )

        // Usage descending: both skills have unknown usage, so the tie-break is name ascending
        // and the group order is unchanged. Give `zulu` the only usage count to flip it.
        manager.skillUsageRecords = [.claudeCode: ["zulu": makeUsageRecord(count: 5)]]
        manager.skillUsageScanStates = [.claudeCode: .available(
            scannedLogCount: 1,
            preservedLogCount: 0,
            failedLogCount: 0
        )]
        viewModel.sortOrder = .usage
        viewModel.sortDirection = .descending
        XCTAssertEqual(
            viewModel.sourceGroups(from: viewModel.filteredSkills).map(\.id),
            ["github:zzz/two", "github:aaa/one"]
        )
    }

    func testInnerOrderRespectsSortDirection() {
        let manager = makeManager()
        let viewModel = DashboardViewModel(skillManager: manager)
        manager.skills = [
            makeSkill(id: "alpha", name: "Alpha", source: "obra/superpowers"),
            makeSkill(id: "zulu", name: "Zulu", source: "obra/superpowers"),
        ]

        viewModel.sortOrder = .name
        viewModel.sortDirection = .ascending
        XCTAssertEqual(
            viewModel.sourceGroups(from: viewModel.filteredSkills)[0].skills.map(\.id),
            ["alpha", "zulu"]
        )

        viewModel.sortDirection = .descending
        XCTAssertEqual(
            viewModel.sourceGroups(from: viewModel.filteredSkills)[0].skills.map(\.id),
            ["zulu", "alpha"]
        )
    }

    // MARK: - Filtering interaction

    func testAgentFilterDropsEmptyGroups() {
        // The group list is derived from the already-filtered array, so a group whose only
        // member was filtered out must vanish rather than render an empty section.
        let manager = makeManager()
        let viewModel = DashboardViewModel(skillManager: manager)
        manager.skills = [
            makeSkill(id: "alpha", name: "Alpha", source: "aaa/one", agents: [.claudeCode]),
            makeSkill(id: "zulu", name: "Zulu", source: "zzz/two", agents: [.codex]),
        ]

        viewModel.selectedAgentFilter = .codex

        let groups = viewModel.sourceGroups(from: viewModel.filteredSkills)

        XCTAssertEqual(groups.map(\.id), ["github:zzz/two"])
        XCTAssertEqual(groups[0].skills.map(\.id), ["zulu"])
    }

    // MARK: - Preferred casing vote

    func testPreferredVariantTieBreak() {
        // Most frequent wins.
        XCTAssertEqual(
            DashboardViewModel.preferredVariant(
                ["crossoverjie/skills": 1, "crossoverJie/skills": 3],
                fallback: "fallback"
            ),
            "crossoverJie/skills"
        )

        // Same frequency → more uppercase letters wins.
        XCTAssertEqual(
            DashboardViewModel.preferredVariant(
                ["crossoverjie/skills": 1, "crossoverJie/skills": 1],
                fallback: "fallback"
            ),
            "crossoverJie/skills"
        )

        // Full tie → lexicographically smaller wins (`max(by:)` keeps the greater element, so
        // the predicate is inverted for this last comparison).
        XCTAssertEqual(
            DashboardViewModel.preferredVariant(
                ["AAA/x": 1, "BBB/x": 1],
                fallback: "fallback"
            ),
            "AAA/x"
        )

        // Empty vote → the caller's fallback survives.
        XCTAssertEqual(
            DashboardViewModel.preferredVariant([:], fallback: "github/repo"),
            "github/repo"
        )
    }

    // MARK: - Source link ("open in browser") button

    func testGitHubGroupExposesWebURL() {
        let viewModel = makeViewModel()
        let skills = [
            makeSkill(
                id: "agent-notifier",
                source: "crossoverJie/skills",
                sourceUrl: "https://github.com/crossoverJie/skills.git"
            ),
        ]

        let groups = viewModel.sourceGroups(from: skills)

        // `.git` is stripped: the browser URL is the repository page, not a clone URL.
        XCTAssertEqual(
            groups[0].webURL?.absoluteString,
            "https://github.com/crossoverJie/skills"
        )
    }

    func testSSHSourceUrlFallsBackToCanonicalWebURL() {
        // Real lock files contain SSH clone URLs (`git@github.com:o/r.git`), which a browser
        // cannot open. The canonical URL is rebuilt from `owner/repo` in that case.
        let viewModel = makeViewModel()
        let skills = [
            makeSkill(
                id: "disk-raccoon",
                source: "orange2ai/disk-raccoon",
                sourceUrl: "git@github.com:orange2ai/disk-raccoon.git"
            ),
        ]

        let groups = viewModel.sourceGroups(from: skills)

        XCTAssertEqual(
            groups[0].webURL?.absoluteString,
            "https://github.com/orange2ai/disk-raccoon"
        )
    }

    func testNonGitHubGroupsHaveNoWebURL() {
        // Local paths, ClawHub slugs and unrecorded sources have no page worth opening, so the
        // header must not render a dead button.
        let viewModel = makeViewModel()
        let skills = [
            makeSkill(id: "slidev", source: "/Users/x/slidev", sourceType: "local"),
            makeSkill(id: "pdf", source: "pdf", sourceType: "clawhub"),
            makeSkill(id: "orphan"),
        ]

        let groups = viewModel.sourceGroups(from: skills)

        XCTAssertEqual(groups.count, 3)
        XCTAssertTrue(groups.allSatisfy { $0.webURL == nil })
    }

    // MARK: - Collapse state

    func testToggleGroupCollapsed() {
        let viewModel = makeViewModel()
        let groupID = "github:obra/superpowers"

        XCTAssertFalse(viewModel.isGroupCollapsed(groupID))
        viewModel.toggleGroupCollapsed(groupID)
        XCTAssertTrue(viewModel.isGroupCollapsed(groupID))
        viewModel.toggleGroupCollapsed(groupID)
        XCTAssertFalse(viewModel.isGroupCollapsed(groupID))
    }

    func testCollapseStateDoesNotHideMembersFromTheModel() {
        // The View decides what to render; `sourceGroups` still reports every member so the
        // header's count stays correct while collapsed.
        let viewModel = makeViewModel()
        let skills = [
            makeSkill(id: "alpha", source: "obra/superpowers"),
            makeSkill(id: "zulu", source: "obra/superpowers"),
        ]

        viewModel.toggleGroupCollapsed("github:obra/superpowers")
        let groups = viewModel.sourceGroups(from: skills)

        XCTAssertEqual(groups[0].skills.count, 2)
    }

    // MARK: - Helpers

    private func makeViewModel() -> DashboardViewModel {
        DashboardViewModel(skillManager: makeManager())
    }

    private func makeManager() -> SkillManager {
        SkillManager(skillUsageProviders: [StubGroupingUsageProvider(agentType: .claudeCode)])
    }

    private func makeUsageRecord(count: Int) -> SkillUsageRecord {
        SkillUsageRecord(detectedInvocationCount: count, lastDetectedAt: nil)
    }

    /// `LockEntry` has seven fields without defaults, so the helper fills every one of them;
    /// only `source` / `sourceType` matter to the grouping logic under test.
    private func makeSkill(
        id: String,
        name: String? = nil,
        source: String? = nil,
        sourceType: String = "github",
        sourceUrl: String? = nil,
        agents: [AgentType] = []
    ) -> Skill {
        Skill(
            id: id,
            canonicalURL: URL(fileURLWithPath: "/tmp/skills/\(id)"),
            metadata: SkillMetadata(name: name ?? id, description: ""),
            markdownBody: "",
            scope: .sharedGlobal,
            installations: agents.map {
                SkillInstallation(
                    agentType: $0,
                    path: URL(fileURLWithPath: "/tmp/\($0.rawValue)/\(id)"),
                    isSymlink: false
                )
            },
            lockEntry: source.map {
                LockEntry(
                    source: $0,
                    sourceType: sourceType,
                    sourceUrl: sourceUrl ?? "https://github.com/\($0).git",
                    skillPath: "skills/\(id)/SKILL.md",
                    skillFolderHash: "hash-\(id)",
                    installedAt: "2026-01-01T00:00:00Z",
                    updatedAt: "2026-01-01T00:00:00Z"
                )
            }
        )
    }
}

/// Minimal usage provider so the manager reports a scanned (not "pending") usage state.
private actor StubGroupingUsageProvider: SkillUsageProvider {
    nonisolated let agentType: AgentType

    init(agentType: AgentType) {
        self.agentType = agentType
    }

    func scan() async -> SkillUsageScanResult {
        SkillUsageScanResult(
            records: [:],
            scannedLogCount: 0,
            preservedLogCount: 0,
            failedLogCount: 0
        )
    }
}
