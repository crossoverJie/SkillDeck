import XCTest
@testable import SkillDeck

/// Unit tests for SkillManager's remote hash caching and transient field restoration.
///
/// These tests verify the fix for a bug where refresh() replaces the skills array with
/// freshly scanned Skill structs, losing remoteTreeHash and remoteCommitHash. The fix
/// uses cachedRemoteTreeHashes/cachedRemoteCommitHashes dictionaries and a
/// restoreTransientSkillFields() method to restore those values after refresh.
///
/// We test restoreTransientSkillFields() directly (extracted from refresh()) to avoid
/// depending on real filesystem scanning that refresh() requires.
///
/// @MainActor is required because SkillManager is @MainActor-isolated — all its
/// properties and methods must be accessed from the main thread.
/// In Swift, marking a test class @MainActor ensures all test methods run on the main actor,
/// similar to Android's @UiThreadTest annotation.
@MainActor
final class SkillManagerUpdateCacheTests: XCTestCase {

    // MARK: - Helpers

    /// Create a minimal Skill struct for testing.
    ///
    /// Uses a dummy file URL for canonicalURL since we never touch the filesystem in these tests.
    /// `installations` is empty and `scope` is `.sharedGlobal` — the simplest valid configuration.
    private func makeSkill(
        id: String,
        remoteTreeHash: String? = nil,
        remoteCommitHash: String? = nil,
        hasUpdate: Bool = false
    ) -> Skill {
        var skill = Skill(
            id: id,
            canonicalURL: URL(fileURLWithPath: "/tmp/test-skills/\(id)"),
            metadata: SkillMetadata(name: id, description: "Test skill \(id)"),
            markdownBody: "",
            scope: .sharedGlobal,
            installations: []
        )
        skill.remoteTreeHash = remoteTreeHash
        skill.remoteCommitHash = remoteCommitHash
        skill.hasUpdate = hasUpdate
        return skill
    }

    // MARK: - cacheRemoteHashes Tests

    /// Verify cacheRemoteHashes stores values, then restoreTransientSkillFields restores them
    /// onto fresh Skill instances that have nil remoteTreeHash/remoteCommitHash.
    func testCacheRemoteHashes_storesAndRestoresValues() async {
        // Arrange: create SkillManager with a skill that has remote hashes
        let manager = SkillManager()
        let skillID = "test-skill"
        let treeHash = "abc123treehash"
        let commitHash = "def456commithash"

        // Cache the remote hashes (simulates what checkForUpdate does)
        manager.cacheRemoteHashes(for: skillID, remoteTreeHash: treeHash, remoteCommitHash: commitHash)

        // Simulate refresh(): replace skills array with fresh structs (no remote hashes)
        manager.skills = [makeSkill(id: skillID)]

        // Act: restore transient fields
        await manager.restoreTransientSkillFields()

        // Assert: remote hashes should be restored from cache
        XCTAssertEqual(manager.skills[0].remoteTreeHash, treeHash,
                       "remoteTreeHash should be restored from cache after refresh")
        XCTAssertEqual(manager.skills[0].remoteCommitHash, commitHash,
                       "remoteCommitHash should be restored from cache after refresh")
    }

    /// Verify that passing nil to cacheRemoteHashes removes cached values,
    /// so subsequent restoreTransientSkillFields does NOT set remote hashes.
    func testCacheRemoteHashes_clearsOnNil() async {
        // Arrange: cache hashes first, then clear them by passing nil
        let manager = SkillManager()
        let skillID = "test-skill"

        manager.cacheRemoteHashes(for: skillID, remoteTreeHash: "some-hash", remoteCommitHash: "some-commit")
        // Clear by passing nil (simulates post-update cleanup)
        manager.cacheRemoteHashes(for: skillID, remoteTreeHash: nil, remoteCommitHash: nil)

        // Simulate refresh(): fresh skill structs
        manager.skills = [makeSkill(id: skillID)]

        // Act
        await manager.restoreTransientSkillFields()

        // Assert: should remain nil since cache was cleared
        XCTAssertNil(manager.skills[0].remoteTreeHash,
                     "remoteTreeHash should be nil after cache was cleared")
        XCTAssertNil(manager.skills[0].remoteCommitHash,
                     "remoteCommitHash should be nil after cache was cleared")
    }

    // MARK: - restoreTransientSkillFields Tests

    /// Core regression test: cache hashes → replace skills array → restore → verify.
    /// This is the exact sequence that happens during a FileSystemWatcher-triggered refresh.
    func testRestoreTransientSkillFields_preservesRemoteHashes() async {
        let manager = SkillManager()

        // Step 1: Set up initial state with remote hashes (simulates checkForUpdate result)
        let skillA = makeSkill(id: "skill-a", remoteTreeHash: "tree-aaa", remoteCommitHash: "commit-aaa")
        let skillB = makeSkill(id: "skill-b", remoteTreeHash: "tree-bbb", remoteCommitHash: "commit-bbb")
        manager.skills = [skillA, skillB]

        // Cache the remote hashes (as checkForUpdate would do)
        manager.cacheRemoteHashes(for: "skill-a", remoteTreeHash: "tree-aaa", remoteCommitHash: "commit-aaa")
        manager.cacheRemoteHashes(for: "skill-b", remoteTreeHash: "tree-bbb", remoteCommitHash: "commit-bbb")

        // Step 2: Simulate refresh() replacing skills with fresh structs (no transient data)
        manager.skills = [makeSkill(id: "skill-a"), makeSkill(id: "skill-b")]

        // Verify transient fields are lost after replacement
        XCTAssertNil(manager.skills[0].remoteTreeHash, "Fresh skill should have nil remoteTreeHash")
        XCTAssertNil(manager.skills[1].remoteTreeHash, "Fresh skill should have nil remoteTreeHash")

        // Step 3: Restore
        await manager.restoreTransientSkillFields()

        // Step 4: Assert restoration
        XCTAssertEqual(manager.skills[0].remoteTreeHash, "tree-aaa")
        XCTAssertEqual(manager.skills[0].remoteCommitHash, "commit-aaa")
        XCTAssertEqual(manager.skills[1].remoteTreeHash, "tree-bbb")
        XCTAssertEqual(manager.skills[1].remoteCommitHash, "commit-bbb")
    }

    /// Verify hasUpdate is restored from updateStatuses dictionary.
    /// updateStatuses persists across refreshes as a separate dictionary on SkillManager.
    func testRestoreTransientSkillFields_restoresHasUpdate() async {
        let manager = SkillManager()

        // Set updateStatuses to simulate a previous update check result
        // updateStatuses is a `var` (not private), so we can set it directly in tests
        manager.updateStatuses["skill-with-update"] = .hasUpdate
        manager.updateStatuses["skill-up-to-date"] = .upToDate
        manager.updateStatuses["skill-not-checked"] = .notChecked

        // Simulate refresh(): fresh skills with hasUpdate = false (default)
        manager.skills = [
            makeSkill(id: "skill-with-update"),
            makeSkill(id: "skill-up-to-date"),
            makeSkill(id: "skill-not-checked"),
        ]

        // Act
        await manager.restoreTransientSkillFields()

        // Assert
        XCTAssertTrue(manager.skills[0].hasUpdate,
                      "hasUpdate should be true when updateStatuses is .hasUpdate")
        XCTAssertFalse(manager.skills[1].hasUpdate,
                       "hasUpdate should be false when updateStatuses is .upToDate")
        XCTAssertFalse(manager.skills[2].hasUpdate,
                       "hasUpdate should be false when updateStatuses is .notChecked")
    }

    /// Verify that after clearing cache (simulating post-update cleanup),
    /// restoreTransientSkillFields does NOT set remote hashes.
    /// This simulates the flow: user clicks Update → updateSkill clears cache → refresh().
    func testCacheCleared_afterUpdate_restoreDoesNotSetHashes() async {
        let manager = SkillManager()
        let skillID = "updated-skill"

        // Simulate: checkForUpdate cached hashes
        manager.cacheRemoteHashes(for: skillID, remoteTreeHash: "old-tree", remoteCommitHash: "old-commit")

        // Simulate: updateSkill clears cache after successful update
        // (This is what updateSkill does at line ~751-752 in SkillManager.swift)
        manager.cacheRemoteHashes(for: skillID, remoteTreeHash: nil, remoteCommitHash: nil)

        // Simulate: refresh() after update replaces skills array
        manager.skills = [makeSkill(id: skillID)]

        // Act
        await manager.restoreTransientSkillFields()

        // Assert: hashes should NOT be restored since cache was cleared
        XCTAssertNil(manager.skills[0].remoteTreeHash,
                     "remoteTreeHash should not be restored after cache was cleared by updateSkill")
        XCTAssertNil(manager.skills[0].remoteCommitHash,
                     "remoteCommitHash should not be restored after cache was cleared by updateSkill")
        XCTAssertFalse(manager.skills[0].hasUpdate,
                       "hasUpdate should remain false when no updateStatuses entry exists")
    }

    /// Verify that skills not in the cache are left untouched (no crash, no unexpected values).
    /// This covers the case where a new skill appears during refresh that was never checked.
    func testRestoreTransientSkillFields_ignoresUncachedSkills() async {
        let manager = SkillManager()

        // Cache hashes for skill-a only
        manager.cacheRemoteHashes(for: "skill-a", remoteTreeHash: "tree-a", remoteCommitHash: "commit-a")

        // Simulate refresh(): both skill-a and a brand-new skill-b appear
        manager.skills = [makeSkill(id: "skill-a"), makeSkill(id: "skill-b")]

        // Act
        await manager.restoreTransientSkillFields()

        // Assert: skill-a is restored, skill-b stays nil
        XCTAssertEqual(manager.skills[0].remoteTreeHash, "tree-a")
        XCTAssertEqual(manager.skills[0].remoteCommitHash, "commit-a")
        XCTAssertNil(manager.skills[1].remoteTreeHash,
                     "Uncached skill should have nil remoteTreeHash")
        XCTAssertNil(manager.skills[1].remoteCommitHash,
                     "Uncached skill should have nil remoteCommitHash")
    }
}
