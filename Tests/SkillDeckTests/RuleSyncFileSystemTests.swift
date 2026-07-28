import XCTest
@testable import SkillDeck

/// RuleSyncFileSystemTests exercise rules separately from skills because their targets are files,
/// and a real file must be backed up before a canonical rules symlink replaces it.
final class RuleSyncFileSystemTests: XCTestCase {
    private var root: URL!
    private var project: ManagedProject!
    private var target: RuleSyncTarget!
    private var filesystem: RuleSyncFileSystem!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SkillDeckRuleSync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        project = ManagedProject(rootPath: root.path)
        target = RuleSyncTarget(
            id: "test",
            name: "Test Agent",
            projectRelativePath: ".test/AGENTS.md",
            globalRelativePath: ".test-global/AGENTS.md"
        )
        filesystem = RuleSyncFileSystem(
            backupRoot: root.appendingPathComponent("backups"),
            targets: [target]
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testMissingSourceDoesNotProduceSynchronizationPlan() {
        XCTAssertFalse(filesystem.sourceExists(for: project))
        XCTAssertTrue(filesystem.syncPlan(for: project).isEmpty)
    }

    func testCreatesCanonicalSourceAndTargetLink() throws {
        try filesystem.createSource(for: project)
        let source = filesystem.sourceURL(for: project)
        let change = try XCTUnwrap(filesystem.syncPlan(for: project).first)

        XCTAssertEqual(change.kind, .createLink)
        _ = try filesystem.apply(change)

        let targetURL = target.url(in: project)
        XCTAssertTrue(SymlinkManager.isSymlink(at: targetURL))
        XCTAssertEqual(SymlinkManager.resolveSymlink(at: targetURL).standardizedFileURL.path, source.standardizedFileURL.path)
    }

    func testExistingRuleIsBackedUpBeforeReplacement() throws {
        try filesystem.createSource(for: project)
        let targetURL = target.url(in: project)
        try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "legacy rule".write(to: targetURL, atomically: true, encoding: .utf8)

        var change = try XCTUnwrap(filesystem.syncPlan(for: project).first)
        XCTAssertEqual(change.kind, .replaceItem)
        XCTAssertEqual(try filesystem.apply(change), "保留 Test Agent 的现有规则")
        XCTAssertFalse(SymlinkManager.isSymlink(at: targetURL))

        change.resolution = .backupAndReplace
        _ = try filesystem.apply(change)
        XCTAssertTrue(SymlinkManager.isSymlink(at: targetURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("backups").path))
    }

    func testRemovalOnlyIncludesManagedRuleLinks() throws {
        try filesystem.createSource(for: project)
        let change = try XCTUnwrap(filesystem.syncPlan(for: project).first)
        _ = try filesystem.apply(change)

        let removal = try XCTUnwrap(filesystem.removePlan(for: project).first)
        XCTAssertEqual(removal.kind, .removeLink)
        _ = try filesystem.apply(removal)

        XCTAssertFalse(FileManager.default.fileExists(atPath: target.url(in: project).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: filesystem.sourceURL(for: project).path))
    }

    func testGlobalInspectionExcludesProjectOnlyTargets() {
        let globalProject = ManagedProject(rootPath: root.path, usesConfiguredGlobalSource: true)
        let globalTarget = RuleSyncTarget(
            id: "global",
            name: "Global Agent",
            projectRelativePath: "AGENTS.md",
            globalRelativePath: ".global/AGENTS.md"
        )
        let projectOnlyTarget = RuleSyncTarget(
            id: "project-only",
            name: "Project Only",
            projectRelativePath: ".github/copilot-instructions.md",
            globalRelativePath: ""
        )
        let scopedFilesystem = RuleSyncFileSystem(targets: [globalTarget, projectOnlyTarget])

        XCTAssertEqual(scopedFilesystem.inspect(project: globalProject).map(\.target.id), ["global"])
    }

    func testCursorRuleReferencesCanonicalSourceAndAppearsAsManaged() throws {
        let cursorTarget = RuleSyncTarget(
            id: "cursor",
            name: "Cursor",
            projectRelativePath: ".cursor/rules/skilldeck.mdc",
            globalRelativePath: "",
            format: .cursorRule
        )
        let cursorFilesystem = RuleSyncFileSystem(targets: [cursorTarget])
        try cursorFilesystem.createSource(for: project)

        let change = try XCTUnwrap(cursorFilesystem.syncPlan(for: project).first)
        _ = try cursorFilesystem.apply(change)

        let contents = try String(contentsOf: cursorTarget.url(in: project), encoding: .utf8)
        XCTAssertTrue(contents.contains("alwaysApply: true"))
        XCTAssertTrue(contents.contains("@../../.agents/AGENTS.md"))
        XCTAssertEqual(cursorFilesystem.inspect(project: project).first?.state, .linked)
    }
}
