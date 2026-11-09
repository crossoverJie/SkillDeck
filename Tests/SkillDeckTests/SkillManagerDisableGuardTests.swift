import XCTest
@testable import SkillDeck

/// Service-layer guard / orchestration tests for the global disable feature.
///
/// The manager is built with an isolated `UserDefaults` suite, a temp lock file and a temp commit
/// cache (mirroring `BatchUpdateTests`), so it never pollutes `UserDefaults.standard` or the real
/// `~/.agents/.skill-lock.json`. Tests that need a real disable/enable round trip create
/// UUID-prefixed directories under the real `~/.agents/skills/` (the only path admissible for
/// `canDisable`) and clean them up in tearDown. Tests that only exercise guards inject synthetic
/// `Skill` structs into `manager.skills` and need no filesystem setup.
@MainActor
final class SkillManagerDisableGuardTests: XCTestCase {

    private let fm = FileManager.default
    private var uuid: String!
    private var tempDir: URL!
    private var lockURL: URL!
    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var createdSharedSkillsDir = false
    private var managedPaths: [URL] = []

    private var shared: URL { SkillScanner.sharedSkillsURL }

    override func setUp() async throws {
        try await super.setUp()
        uuid = UUID().uuidString
        suiteName = "SkillDeckDisableGuard-\(uuid!)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        tempDir = fm.temporaryDirectory.appendingPathComponent("SkillDeckDisableGuard-\(uuid!)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        lockURL = tempDir.appendingPathComponent(".test-skill-lock.json")
        let emptyLock = LockFile(version: 3, skills: [:], dismissed: [:], lastSelectedAgents: [])
        try JSONEncoder().encode(emptyLock).write(to: lockURL)

        if !fm.fileExists(atPath: shared.path) {
            try fm.createDirectory(at: shared, withIntermediateDirectories: true)
            createdSharedSkillsDir = true
        }
    }

    override func tearDown() async throws {
        for url in managedPaths {
            try? fm.removeItem(at: url)
        }
        for agent in AgentType.allCases {
            let link = agent.skillsDirectoryURL.appendingPathComponent(uuid)
            if SymlinkManager.isSymlink(at: link) {
                try? fm.removeItem(at: link)
            }
        }
        if createdSharedSkillsDir,
           let contents = try? fm.contentsOfDirectory(atPath: shared.path),
           contents.isEmpty {
            try? fm.removeItem(at: shared)
        }
        if let suiteName { testDefaults?.removePersistentDomain(forName: suiteName) }
        if let tempDir { try? fm.removeItem(at: tempDir) }
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeManager(gitService: any GitServiceProtocol = MockGitService()) -> SkillManager {
        SkillManager(
            gitService: gitService,
            lockFileManager: LockFileManager(filePath: lockURL),
            commitHashCache: CommitHashCache(filePath: tempDir.appendingPathComponent(".test-skilldeck-cache.json")),
            userDefaults: testDefaults,
            recoveryRoots: []
        )
    }

    /// Create a REAL canonical skill directory (admissible for `canDisable`).
    @discardableResult
    private func makeCanonicalSkill(_ suffix: String, withContent: Bool = true) throws -> (dir: URL, skill: Skill) {
        let name = "\(uuid!)-\(suffix)"
        let dir = shared.appendingPathComponent(name)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        managedPaths.append(dir)
        if withContent {
            try "---\nname: \(name)\n---\ncontent".write(
                to: SkillDisableManager.skillMDURL(for: dir),
                atomically: true, encoding: .utf8
            )
        }
        let skill = Skill(
            id: name,
            canonicalURL: dir,
            metadata: SkillMetadata(name: name, description: ""),
            markdownBody: "",
            scope: .sharedGlobal,
            installations: []
        )
        return (dir, skill)
    }

    private func makeSyntheticSkill(name: String, canonicalURL: URL, scope: SkillScope = .sharedGlobal) -> Skill {
        Skill(
            id: name,
            canonicalURL: canonicalURL,
            metadata: SkillMetadata(name: name, description: ""),
            markdownBody: "",
            scope: scope,
            installations: []
        )
    }

    private func githubLockEntry(repoURL: String) -> LockEntry {
        LockEntry(
            source: "test-owner/test-repo",
            sourceType: "github",
            sourceUrl: repoURL,
            skillPath: "SKILL.md",
            skillFolderHash: "old-hash",
            installedAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )
    }

    private func addLockEntry(_ entry: LockEntry, for id: String) throws {
        var lock = try JSONDecoder().decode(LockFile.self, from: Data(contentsOf: lockURL))
        lock.skills[id] = entry
        try JSONEncoder().encode(lock).write(to: lockURL)
    }

    // MARK: - Admission: rejected skills cause no FS change

    func testExternalAndAgentDirectorySkillsAreRejectedWithoutFSChanges() async throws {
        let manager = makeManager()

        let externalURL = tempDir.appendingPathComponent("external-\(uuid!)")
        let external = makeSyntheticSkill(name: "\(uuid!)-external", canonicalURL: externalURL)
        XCTAssertFalse(manager.canToggleDisabled(id: external.id))
        manager.skills = [external]
        do {
            try await manager.setSkillDisabled(external, disabled: true)
            XCTFail("external location must be refused")
        } catch let error as SkillDisableManager.DisableError {
            guard case .externalLocation = error else { return XCTFail("wrong error: \(error)") }
        }
        XCTAssertFalse(fm.fileExists(atPath: externalURL.path), "no directory should be created")

        let agentURL = AgentType.claudeCode.skillsDirectoryURL.appendingPathComponent("\(uuid!)-agent")
        let agentDirSkill = makeSyntheticSkill(name: "\(uuid!)-agent", canonicalURL: agentURL)
        XCTAssertFalse(manager.canToggleDisabled(id: agentDirSkill.id))
        manager.skills = [agentDirSkill]
        do {
            try await manager.setSkillDisabled(agentDirSkill, disabled: true)
            XCTFail("agent-directory skill must be refused")
        } catch let error as SkillDisableManager.DisableError {
            guard case .agentDirectoryLocation = error else { return XCTFail("wrong error: \(error)") }
        }
        XCTAssertFalse(fm.fileExists(atPath: agentURL.path))
    }

    func testCanToggleDisabledMatchesSetSkillDisabledAdmission() async throws {
        let manager = makeManager()
        let (_, canonical) = try makeCanonicalSkill("consistent")
        manager.skills = [canonical]
        XCTAssertTrue(manager.canToggleDisabled(id: canonical.id))
        do {
            try await manager.setSkillDisabled(canonical, disabled: true)
        } catch {
            XCTFail("canToggleDisabled(id:) said yes but setSkillDisabled refused: \(error)")
        }

        let agentURL = AgentType.claudeCode.skillsDirectoryURL.appendingPathComponent("\(uuid!)-nope")
        let rejected = makeSyntheticSkill(name: "\(uuid!)-nope", canonicalURL: agentURL)
        manager.skills = [rejected]
        XCTAssertFalse(manager.canToggleDisabled(id: rejected.id))
        do {
            try await manager.setSkillDisabled(rejected, disabled: true)
            XCTFail("setSkillDisabled must agree with canToggleDisabled(id:)")
        } catch is SkillDisableManager.DisableError {
            // expected
        }
    }

    // MARK: - Lock file stays byte-identical across a disable/enable cycle

    func testDisableEnableCycleDoesNotTouchLockFile() async throws {
        let manager = makeManager()
        let (dir, skill) = try makeCanonicalSkill("lock")
        manager.skills = [skill]

        let before = try Data(contentsOf: lockURL)
        try await manager.setSkillDisabled(skill, disabled: true)
        let current = try XCTUnwrap(manager.latest(id: skill.id))
        try await manager.setSkillDisabled(current, disabled: false)
        let after = try Data(contentsOf: lockURL)

        XCTAssertEqual(before, after, "disable/enable must not read-modify-write the lock file")
        XCTAssertFalse(fm.fileExists(atPath: SkillDisableManager.markerURL(for: dir).path))
        XCTAssertTrue(fm.fileExists(atPath: SkillDisableManager.skillMDURL(for: dir).path))
    }

    // MARK: - Service-layer guards on write operations

    func testSaveSkillAndToggleAssignmentAreBlockedWhileDisabled() async throws {
        let manager = makeManager()
        let (_, base) = try makeCanonicalSkill("guard")
        var disabledSkill = base
        disabledSkill.isDisabled = true
        manager.skills = [disabledSkill]

        do {
            try await manager.saveSkill(disabledSkill,
                                        metadata: SkillMetadata(name: "x", description: ""),
                                        markdownBody: "new")
            XCTFail("saveSkill must refuse a disabled skill")
        } catch let error as SkillDisableManager.DisableError {
            guard case .skillIsDisabled = error else { return XCTFail("wrong error: \(error)") }
        }

        // toggleAssignment returns silently (matching inherited-installation handling) and must
        // not create any symlink for a disabled skill.
        try await manager.toggleAssignment(disabledSkill, agent: .claudeCode)
        let link = AgentType.claudeCode.skillsDirectoryURL.appendingPathComponent(disabledSkill.id)
        XCTAssertFalse(SymlinkManager.isSymlink(at: link),
                       "assignments must stay frozen while disabled")
    }

    func testAssignAndUnassignAreBlockedWhileDisabled() async throws {
        let manager = makeManager()
        let (_, base) = try makeCanonicalSkill("assign-guard")
        var disabledSkill = base
        disabledSkill.isDisabled = true
        manager.skills = [disabledSkill]

        try await manager.assignSkill(disabledSkill, to: .claudeCode)
        try await manager.unassignSkill(disabledSkill, from: .claudeCode)
        let link = AgentType.claudeCode.skillsDirectoryURL.appendingPathComponent(disabledSkill.id)
        XCTAssertFalse(SymlinkManager.isSymlink(at: link))
    }

    func testUpdateSkillBlockedWhenDisabledButAllowsBroken() async throws {
        let manager = makeManager()
        let (_, base) = try makeCanonicalSkill("update-guard")

        var disabled = base
        disabled.isDisabled = true
        manager.skills = [disabled]
        do {
            try await manager.updateSkill(disabled, remoteHash: "x")
            XCTFail("updateSkill must refuse a disabled skill")
        } catch let error as SkillDisableManager.DisableError {
            guard case .skillIsDisabled = error else { return XCTFail("wrong error: \(error)") }
        }

        // A broken skill MUST pass the new `!isDisabled` guard. With no lockEntry, updateSkill
        // returns early at its own guard — the important part is that it is NOT blocked here.
        var broken = base
        broken.isBroken = true
        manager.skills = [broken]
        do {
            try await manager.updateSkill(broken)
        } catch {
            XCTFail("broken skill must not be blocked by the disable guard: \(error)")
        }
    }

    func testDeleteDisabledSkillSucceeds() async throws {
        let manager = makeManager()
        let (dir, skill) = try makeCanonicalSkill("delete-disabled")
        manager.skills = [skill]

        try await manager.setSkillDisabled(skill, disabled: true)
        XCTAssertTrue(fm.fileExists(atPath: SkillDisableManager.markerURL(for: dir).path))

        let current = try XCTUnwrap(manager.latest(id: skill.id))
        try await manager.deleteSkill(current)
        XCTAssertFalse(fm.fileExists(atPath: dir.path),
                       "deleting a disabled skill must remove the directory (marker included)")
    }

    // MARK: - Concurrency guards

    func testSetSkillDisabledRejectsBatchUpdateInProgress() async throws {
        let manager = makeManager()
        let (_, skill) = try makeCanonicalSkill("batch-flag")
        manager.skills = [skill]

        manager.isUpdatingAllSkills = true
        defer { manager.isUpdatingAllSkills = false }
        do {
            try await manager.setSkillDisabled(skill, disabled: true)
            XCTFail("must reject while isUpdatingAllSkills")
        } catch let error as SkillManager.SkillUpdateError {
            XCTAssertEqual(error, .batchUpdateInProgress)
        }
        XCTAssertTrue(fm.fileExists(atPath: SkillDisableManager.skillMDURL(for: skill.canonicalURL).path),
                      "no FS change on rejection")
    }

    func testSetSkillDisabledRejectsCheckPhaseInProgress() async throws {
        let manager = makeManager()
        let (_, skill) = try makeCanonicalSkill("check-flag")
        manager.skills = [skill]

        // The check phase of updateAllSkills() intentionally keeps isUpdatingAllSkills == false,
        // so `isCheckingUpdates` must ALSO be guarded.
        manager.isCheckingUpdates = true
        defer { manager.isCheckingUpdates = false }
        do {
            try await manager.setSkillDisabled(skill, disabled: true)
            XCTFail("must reject while isCheckingUpdates")
        } catch let error as SkillManager.SkillUpdateError {
            XCTAssertEqual(error, .batchUpdateInProgress)
        }
    }

    func testSetSkillDisabledRejectsIndividualUpdateInProgress() async throws {
        let manager = makeManager()
        let (_, skill) = try makeCanonicalSkill("individual-flag")
        manager.skills = [skill]

        manager.updatingSkillIDs.insert(skill.id)
        defer { manager.updatingSkillIDs.remove(skill.id) }
        do {
            try await manager.setSkillDisabled(skill, disabled: true)
            XCTFail("must reject while a single update owns the id")
        } catch let error as SkillManager.SkillUpdateError {
            XCTAssertEqual(error, .individualUpdateInProgress)
        }
    }

    // MARK: - Transient state cleanup

    func testDisablingClearsUpdateStatus() async throws {
        let manager = makeManager()
        let (_, skill) = try makeCanonicalSkill("status")
        manager.skills = [skill]
        manager.updateStatuses[skill.id] = .hasUpdate

        try await manager.setSkillDisabled(skill, disabled: true)

        XCTAssertEqual(manager.updateStatuses[skill.id], .notChecked,
                       "restoreTransientSkillFields() rebuilds hasUpdate from this dictionary")
        XCTAssertEqual(manager.latest(id: skill.id)?.isDisabled, true)
    }

    // MARK: - refresh() ghost-row filter

    func testRefreshFiltersUnreferencedBrokenRowsButKeepsReferencedOnes() async throws {
        // A: broken, no lockEntry, no direct installation → filtered out.
        let (_, skillA) = try makeCanonicalSkill("ghost-a", withContent: false)
        // B: broken with a direct symlink installation → kept.
        let (dirB, skillB) = try makeCanonicalSkill("ghost-b", withContent: false)
        try SymlinkManager.createSymlink(from: dirB, to: .claudeCode)
        managedPaths.append(
            AgentType.claudeCode.skillsDirectoryURL.appendingPathComponent(skillB.id)
        )
        // C: broken with a lockEntry → kept.
        let (_, skillC) = try makeCanonicalSkill("ghost-c", withContent: false)
        try addLockEntry(githubLockEntry(repoURL: "https://example.com/r.git"), for: skillC.id)

        let manager = makeManager()
        await manager.refresh()

        XCTAssertNil(manager.latest(id: skillA.id),
                     "unreferenced broken directory must not become a ghost row")
        XCTAssertEqual(manager.latest(id: skillB.id)?.isBroken, true,
                       "broken skill with a direct install must stay visible")
        XCTAssertEqual(manager.latest(id: skillC.id)?.isBroken, true,
                       "broken skill with a lock entry must stay visible")
    }

    // MARK: - v5 R1: toggle direction comes from latest(id:), not a stale view snapshot

    func testToggleSkillDisabledDerivesDirectionFromLatest() async throws {
        let manager = makeManager()
        let (dir, skill) = try makeCanonicalSkill("direction")
        manager.skills = [skill]  // freshest state: active

        // Simulate the v4 bug: a view still holds a stale DISABLED snapshot (e.g. it rendered
        // before a watcher refresh re-marked the skill active). The menu label would say
        // "Disable" because the freshest state is active, yet v4's VM computed
        // `!staleSnapshot.isDisabled` = false and ENABLED instead. The new API takes only an id,
        // so the stale struct cannot influence the direction at all.
        var staleSnapshot = skill
        staleSnapshot.isDisabled = true
        XCTAssertTrue(staleSnapshot.isDisabled)

        try await manager.toggleSkillDisabled(id: skill.id)

        XCTAssertTrue(fm.fileExists(atPath: SkillDisableManager.markerURL(for: dir).path),
                      "freshest state was active ⇒ must DISABLE, not ENABLE")
        XCTAssertFalse(fm.fileExists(atPath: SkillDisableManager.skillMDURL(for: dir).path))
        XCTAssertEqual(manager.latest(id: skill.id)?.isDisabled, true)

        // A second toggle re-reads latest(id:) (now disabled) and enables — direction is always
        // derived from the authoritative array, never from any passed snapshot.
        try await manager.toggleSkillDisabled(id: skill.id)
        XCTAssertTrue(fm.fileExists(atPath: SkillDisableManager.skillMDURL(for: dir).path))
        XCTAssertEqual(manager.latest(id: skill.id)?.isDisabled, false)
    }

    // MARK: - broken reinstall path (no self-deadlock)

    func testReinstallBrokenSkillRebuildsViaUpdateSkillWithoutSelfDeadlock() async throws {
        let name = "\(uuid!)-broken"
        let dir = shared.appendingPathComponent(name)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        managedPaths.append(dir)  // no SKILL.md and no marker ⇒ broken

        let repoURL = "https://example.com/rebuild.git"
        let repoDir = tempDir.appendingPathComponent("mock-rebuild-repo")
        try fm.createDirectory(at: repoDir, withIntermediateDirectories: true)
        try "---\nname: \(name)\n---\nrebuilt".write(
            to: repoDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )

        let mock = MockGitService()
        await mock.setRepoDir(repoDir, for: repoURL)
        let manager = makeManager(gitService: mock)

        var broken = makeSyntheticSkill(name: name, canonicalURL: dir)
        broken.isBroken = true
        broken.lockEntry = githubLockEntry(repoURL: repoURL)
        manager.skills = [broken]

        // Must NOT throw: reinstallBrokenSkill deliberately does not reserve updatingSkillIDs
        // (updateSkill owns it), so the recovery path cannot deadlock itself.
        do {
            try await manager.reinstallBrokenSkill(broken)
        } catch {
            XCTFail("reinstallBrokenSkill should not throw: \(error)")
        }

        XCTAssertTrue(fm.fileExists(atPath: SkillDisableManager.skillMDURL(for: dir).path),
                      "SKILL.md must be rebuilt from the source repository")
        let cloneCalls = await mock.cloneCalls
        XCTAssertTrue(cloneCalls.contains(repoURL), "updateSkill must actually clone the repo")
        XCTAssertEqual(manager.latest(id: name)?.isBroken, false)
    }

    func testBrokenSkillWithoutGithubSourceThrowsManualReinstall() async throws {
        let manager = makeManager()
        let (_, base) = try makeCanonicalSkill("no-repo", withContent: false)
        var broken = base
        broken.isBroken = true
        broken.lockEntry = nil
        manager.skills = [broken]

        do {
            try await manager.reinstallBrokenSkill(broken)
            XCTFail("no github lockEntry ⇒ cannot auto-rebuild")
        } catch let error as SkillDisableManager.DisableError {
            guard case .brokenNeedsManualReinstall = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    // MARK: - v5 R2: DashboardViewModel can reach the reinstall path

    func testDashboardViewModelReinstallBrokenSkillGoesThroughSkillManager() async throws {
        let name = "\(uuid!)-vm-broken"
        let dir = shared.appendingPathComponent(name)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        managedPaths.append(dir)

        let repoURL = "https://example.com/vm-rebuild.git"
        let repoDir = tempDir.appendingPathComponent("mock-vm-rebuild-repo")
        try fm.createDirectory(at: repoDir, withIntermediateDirectories: true)
        try "---\nname: \(name)\n---\nrebuilt".write(
            to: repoDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )

        let mock = MockGitService()
        await mock.setRepoDir(repoDir, for: repoURL)
        let manager = makeManager(gitService: mock)

        var broken = makeSyntheticSkill(name: name, canonicalURL: dir)
        broken.isBroken = true
        broken.lockEntry = githubLockEntry(repoURL: repoURL)
        manager.skills = [broken]

        let dashboardVM = DashboardViewModel(skillManager: manager)
        await dashboardVM.reinstallBrokenSkill(broken)

        XCTAssertTrue(fm.fileExists(atPath: SkillDisableManager.skillMDURL(for: dir).path),
                      "DashboardViewModel must forward the reinstall to SkillManager")
        let cloneCalls = await mock.cloneCalls
        XCTAssertTrue(cloneCalls.contains(repoURL))
        XCTAssertNil(manager.errorMessage, "success must not surface an error")
    }

    func testDashboardViewModelToggleSkillDisabledGoesThroughSkillManager() async throws {
        let manager = makeManager()
        let (dir, skill) = try makeCanonicalSkill("vm-toggle")
        manager.skills = [skill]

        let dashboardVM = DashboardViewModel(skillManager: manager)
        await dashboardVM.toggleSkillDisabled(id: skill.id)

        XCTAssertTrue(fm.fileExists(atPath: SkillDisableManager.markerURL(for: dir).path))
        XCTAssertNil(manager.errorMessage)
    }

    // MARK: - P1 regression: a duplicate appearing while disabled must NOT strand the skill

    func testDisabledSkillWithRealDuplicateCanBeEnabledViaToggle() async throws {
        let manager = makeManager()
        let (dir, skill) = try makeCanonicalSkill("stranded-toggle")
        manager.skills = [skill]

        try await manager.setSkillDisabled(skill, disabled: true)
        XCTAssertTrue(fm.fileExists(atPath: SkillDisableManager.markerURL(for: dir).path))

        // A real duplicate shows up in an agent directory while the skill is off (npx / manual
        // copy). Simulate it on the freshest model struct, exactly as the scanner would report it.
        // Under the old single-direction `canDisable` gate, EVERY UI path (switch / toolbar /
        // context menu) refused and the error nonsensically said "Disabling the shared copy...".
        var disabled = try XCTUnwrap(manager.latest(id: skill.id))
        disabled.installations.append(SkillInstallation(
            agentType: .claudeCode,
            path: AgentType.claudeCode.skillsDirectoryURL.appendingPathComponent(skill.id),
            isSymlink: false,
            isInherited: false
        ))
        manager.skills = [disabled]

        XCTAssertFalse(SkillDisableManager.canDisable(disabled), "duplicate blocks DISABLING")
        XCTAssertTrue(SkillDisableManager.canEnable(disabled), "duplicate must NOT block ENABLING")
        XCTAssertTrue(manager.canToggleDisabled(id: skill.id),
                      "detail switch / toolbar / context menu must stay usable")

        // The real UI path is id-only; direction is derived from latest(id:) inside the manager.
        try await manager.toggleSkillDisabled(id: skill.id)

        XCTAssertTrue(fm.fileExists(atPath: SkillDisableManager.skillMDURL(for: dir).path),
                      "skill must be recoverable to SKILL.md")
        XCTAssertFalse(fm.fileExists(atPath: SkillDisableManager.markerURL(for: dir).path))
        XCTAssertEqual(manager.latest(id: skill.id)?.isDisabled, false)
    }

    func testDisabledSkillWithRealDuplicateCanBeEnabledViaMainSwitchBinding() async throws {
        let manager = makeManager()
        let (dir, skill) = try makeCanonicalSkill("stranded-binding")
        manager.skills = [skill]

        try await manager.setSkillDisabled(skill, disabled: true)

        var disabled = try XCTUnwrap(manager.latest(id: skill.id))
        disabled.installations.append(SkillInstallation(
            agentType: .claudeCode,
            path: AgentType.claudeCode.skillsDirectoryURL.appendingPathComponent(skill.id),
            isSymlink: false,
            isInherited: false
        ))
        manager.skills = [disabled]

        // The main availability switch Binding passes an explicit `disabled: false` direction.
        try await manager.setSkillDisabled(disabled, disabled: false)

        XCTAssertTrue(fm.fileExists(atPath: SkillDisableManager.skillMDURL(for: dir).path))
        XCTAssertEqual(manager.latest(id: skill.id)?.isDisabled, false)
    }

    // MARK: - P2b regression: external (CLI/Finder) disable leaves the model stale

    func testExternalDisableIsBlockedByFilesystemGuards() async throws {
        let manager = makeManager()
        let (dir, skill) = try makeCanonicalSkill("external-disable")
        manager.skills = [skill]  // model says ACTIVE

        // The rename happens INSIDE <skill>/. The parent-directory watcher does NOT observe it,
        // so no FSEvent fires and `manager.skills` still reports isDisabled == false.
        try SkillDisableManager.setDisabled(true, at: dir)
        XCTAssertEqual(manager.latest(id: skill.id)?.isDisabled, false, "model is stale")
        XCTAssertTrue(SkillDisableManager.isDisabled(at: dir), "filesystem is disabled")

        // saveSkill: model guard passes, FS guard must stop it from writing a second SKILL.md.
        do {
            try await manager.saveSkill(skill,
                                        metadata: SkillMetadata(name: "x", description: ""),
                                        markdownBody: "edited")
            XCTFail("saveSkill must be blocked by the FS-level guard")
        } catch let error as SkillDisableManager.DisableError {
            guard case .skillIsDisabled = error else { return XCTFail("wrong error: \(error)") }
        }
        XCTAssertFalse(fm.fileExists(atPath: SkillDisableManager.skillMDURL(for: dir).path),
                       "no second SKILL.md may be created (would be a .conflict state)")
        XCTAssertTrue(fm.fileExists(atPath: SkillDisableManager.markerURL(for: dir).path),
                      "marker content must be untouched")

        // linkSkillToRepository: must be blocked BEFORE removeItem + copyItem deletes the marker.
        do {
            try await manager.linkSkillToRepository(skill, repoInput: "owner/repo")
            XCTFail("linkSkillToRepository must be blocked by the FS-level guard")
        } catch let error as SkillDisableManager.DisableError {
            guard case .skillIsDisabled = error else { return XCTFail("wrong error: \(error)") }
        }
        XCTAssertTrue(fm.fileExists(atPath: SkillDisableManager.markerURL(for: dir).path))

        // updateSkill: must be blocked BEFORE a pointless network clone / whole-directory swap.
        var withLock = skill
        withLock.lockEntry = githubLockEntry(repoURL: "https://example.com/r.git")
        manager.skills = [withLock]
        do {
            try await manager.updateSkill(withLock)
            XCTFail("updateSkill must be blocked by the FS-level guard")
        } catch let error as SkillDisableManager.DisableError {
            guard case .skillIsDisabled = error else { return XCTFail("wrong error: \(error)") }
        }
        XCTAssertTrue(fm.fileExists(atPath: SkillDisableManager.markerURL(for: dir).path))
    }

    func testBatchUpdateDoesNotSwapExternallyDisabledSkill() async throws {
        let repoURL = "https://example.com/batch.git"
        let mock = MockGitService()
        let manager = makeManager(gitService: mock)
        let (dir, base) = try makeCanonicalSkill("batch-external")
        var skill = base
        skill.lockEntry = githubLockEntry(repoURL: repoURL)
        manager.skills = [skill]
        manager.updateStatuses[skill.id] = .hasUpdate  // makes updateAllSkills pick it up

        // Externally disabled: model is stale, so the `skillsToUpdate` filter still includes it.
        // Only applySkillUpdate's FS-level guard can prevent the whole-directory swap from
        // backing up and then deleting the marker (permanent content loss).
        try SkillDisableManager.setDisabled(true, at: dir)

        await manager.updateAllSkills()

        XCTAssertTrue(fm.fileExists(atPath: SkillDisableManager.markerURL(for: dir).path),
                      "applySkillUpdate FS guard must protect the marker on the batch path")
        XCTAssertFalse(fm.fileExists(atPath: SkillDisableManager.skillMDURL(for: dir).path))
    }
}
