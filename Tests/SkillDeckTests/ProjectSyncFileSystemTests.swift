import XCTest
@testable import SkillDeck

/// Project sync tests cover whole-directory migration only; partial per-skill synchronization is unsupported.
final class ProjectSyncFileSystemTests: XCTestCase {
    private var root: URL!
    private var project: ManagedProject!
    private var filesystem: ProjectSyncFileSystem!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SkillDeckProjectSync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        project = ManagedProject(rootPath: root.path)
        filesystem = ProjectSyncFileSystem(backupRoot: root.appendingPathComponent("backups"))
        try makeSkill(named: "demo")
        try makeSkill(named: "other")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCreatesWholeDirectoryLinkWhenTargetIsMissing() throws {
        let codex = ProjectAgent.all.first { $0.id == "codex" }!
        let target = root.appendingPathComponent(".codex/skills")

        let inspection = filesystem.inspect(project: project, agent: codex)
        let change = try XCTUnwrap(filesystem.syncPlan(for: inspection).first)
        XCTAssertEqual(change.kind, .createDirectoryLink)
        XCTAssertEqual(Set(change.skillNames), ["demo", "other"])
        _ = try filesystem.apply(change)

        XCTAssertTrue(SymlinkManager.isSymlink(at: target))
        XCTAssertEqual(SymlinkManager.resolveSymlink(at: target).standardizedFileURL.path, project.sourceSkillsURL.standardizedFileURL.path)
    }

    func testAlreadyManagedDirectoryLinkNeedsNoSync() throws {
        let claude = ProjectAgent.all.first { $0.id == "claude-code" }!
        let target = root.appendingPathComponent(".claude/skills")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: project.sourceSkillsURL)

        let inspection = filesystem.inspect(project: project, agent: claude)
        XCTAssertTrue(filesystem.syncPlan(for: inspection).isEmpty)
    }

    func testReplacesExistingDirectoryAfterBackup() throws {
        let claude = ProjectAgent.all.first { $0.id == "claude-code" }!
        let target = root.appendingPathComponent(".claude/skills")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try "legacy".write(to: target.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)

        let inspection = filesystem.inspect(project: project, agent: claude)
        var change = try XCTUnwrap(filesystem.syncPlan(for: inspection).first)
        XCTAssertEqual(change.kind, .replaceDirectory)
        XCTAssertEqual(try filesystem.apply(change), "保留目标 skills 目录")
        XCTAssertFalse(SymlinkManager.isSymlink(at: target))

        change.resolution = .backupAndReplace
        _ = try filesystem.apply(change)
        XCTAssertTrue(SymlinkManager.isSymlink(at: target))
        XCTAssertEqual(SymlinkManager.resolveSymlink(at: target).standardizedFileURL.path, project.sourceSkillsURL.standardizedFileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("backups").path))
    }

    func testReplacesForeignDirectoryLinkAfterBackup() throws {
        let claude = ProjectAgent.all.first { $0.id == "claude-code" }!
        let oldRoot = root.appendingPathComponent(".ai-global/skills")
        try FileManager.default.createDirectory(at: oldRoot, withIntermediateDirectories: true)
        let target = root.appendingPathComponent(".claude/skills")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: oldRoot)

        let inspection = filesystem.inspect(project: project, agent: claude)
        var change = try XCTUnwrap(filesystem.syncPlan(for: inspection).first)
        XCTAssertEqual(change.kind, .replaceDirectory)
        change.resolution = .backupAndReplace
        _ = try filesystem.apply(change)

        XCTAssertEqual(SymlinkManager.resolveSymlink(at: target).standardizedFileURL.path, project.sourceSkillsURL.standardizedFileURL.path)
    }

    func testRemovePlanOnlyRemovesManagedDirectoryLink() throws {
        let gemini = ProjectAgent.all.first { $0.id == "gemini-cli" }!
        let target = root.appendingPathComponent(".gemini/skills")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: project.sourceSkillsURL)

        let inspection = filesystem.inspect(project: project, agent: gemini)
        let change = try XCTUnwrap(filesystem.removePlan(for: inspection).first)
        XCTAssertEqual(change.kind, .removeDirectoryLink)
        _ = try filesystem.apply(change)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.sourceSkillsURL.path))
    }

    func testSyncAllTargetsBuildsAndAppliesOneDirectoryPlanPerTool() throws {
        let codex = try XCTUnwrap(ProjectAgent.all.first { $0.id == "codex" })
        let cursor = try XCTUnwrap(ProjectAgent.all.first { $0.id == "cursor" })
        let plans = [codex, cursor].flatMap { agent in
            filesystem.syncPlan(for: filesystem.inspect(project: project, agent: agent))
        }

        XCTAssertEqual(plans.count, 2)
        for plan in plans {
            XCTAssertEqual(plan.kind, .createDirectoryLink)
            _ = try filesystem.apply(plan)
        }

        for agent in [codex, cursor] {
            let target = agent.skillsURL(in: project)
            XCTAssertTrue(SymlinkManager.isSymlink(at: target))
            XCTAssertEqual(SymlinkManager.resolveSymlink(at: target).standardizedFileURL.path, project.sourceSkillsURL.standardizedFileURL.path)
        }
    }

    private func makeSkill(named name: String) throws {
        let skill = project.sourceSkillsURL.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try "---\nname: \(name)\ndescription: test\n---\n".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
}
