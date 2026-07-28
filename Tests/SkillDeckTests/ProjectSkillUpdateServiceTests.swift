import XCTest
@testable import SkillDeck

/// Verifies that project update metadata stays under the project rather than the global skill store.
final class ProjectSkillUpdateServiceTests: XCTestCase {
    private var projectRoot: URL!
    private var sourceRoot: URL!
    private var skillDirectory: URL!
    private var archiveRoot: URL!

    override func setUpWithError() throws {
        projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("SkillDeckProjectUpdate-\(UUID().uuidString)")
        sourceRoot = projectRoot.appendingPathComponent(".agents/skills")
        skillDirectory = sourceRoot.appendingPathComponent("demo")
        archiveRoot = projectRoot.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try "---\nname: Demo\ndescription: Project test\n---\n\n# Demo\n".write(
            to: skillDirectory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: projectRoot)
    }

    func testLoadsRepositoryMetadataFromProjectLockFile() async throws {
        let projectLockURL = projectRoot.appendingPathComponent(".agents/.skill-lock.json")
        let lockManager = LockFileManager(filePath: projectLockURL)
        try await lockManager.createIfNotExists()
        let expectedEntry = LockEntry(
            source: "owner/repository",
            sourceType: "github",
            sourceUrl: "https://github.com/owner/repository.git",
            skillPath: "skills/demo/SKILL.md",
            skillFolderHash: "project-tree-hash",
            installedAt: "2026-07-14T00:00:00Z",
            updatedAt: "2026-07-14T00:00:00Z"
        )
        try await lockManager.updateEntry(skillName: "demo", entry: expectedEntry)

        let service = ProjectSkillUpdateService(sourceRoot: sourceRoot, disabledSkillStore: DisabledSkillStore(root: archiveRoot))
        let skill = try await service.loadSkill(named: "demo", at: skillDirectory)

        XCTAssertEqual(skill.canonicalURL, skillDirectory)
        guard case .project(let scopedProjectURL) = skill.scope else {
            return XCTFail("Expected project skill scope")
        }
        XCTAssertEqual(scopedProjectURL.standardizedFileURL.path, projectRoot.standardizedFileURL.path)
        XCTAssertEqual(skill.lockEntry, expectedEntry)
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectLockURL.path))
    }

    func testDisableMovesOnlyProjectSkillAndKeepsProjectLockEntry() async throws {
        let secondSkill = sourceRoot.appendingPathComponent("keep")
        try FileManager.default.createDirectory(at: secondSkill, withIntermediateDirectories: true)
        try "---\nname: Keep\n---\n".write(to: secondSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let lockManager = LockFileManager(filePath: projectRoot.appendingPathComponent(".agents/.skill-lock.json"))
        try await lockManager.createIfNotExists()
        let entry = LockEntry(source: "owner/repository", sourceType: "github", sourceUrl: "https://github.com/owner/repository.git", skillPath: "demo/SKILL.md", skillFolderHash: "hash", installedAt: "2026-07-14T00:00:00Z", updatedAt: "2026-07-14T00:00:00Z")
        try await lockManager.updateEntry(skillName: "demo", entry: entry)
        try await lockManager.updateEntry(skillName: "keep", entry: entry)

        let service = ProjectSkillUpdateService(sourceRoot: sourceRoot, disabledSkillStore: DisabledSkillStore(root: archiveRoot))
        let skill = try await service.loadSkill(named: "demo", at: skillDirectory)
        try await service.disableSkill(skill, projectName: "Test Project")

        await lockManager.invalidateCache()
        let deletedEntry = try await lockManager.getEntry(skillName: "demo")
        let retainedEntry = try await lockManager.getEntry(skillName: "keep")
        XCTAssertFalse(FileManager.default.fileExists(atPath: skillDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondSkill.path))
        XCTAssertEqual(deletedEntry, entry)
        XCTAssertEqual(retainedEntry, entry)
    }
}
