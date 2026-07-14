import XCTest
@testable import SkillDeck

/// Verifies that project update metadata stays under the project rather than the global skill store.
final class ProjectSkillUpdateServiceTests: XCTestCase {
    private var projectRoot: URL!
    private var sourceRoot: URL!
    private var skillDirectory: URL!

    override func setUpWithError() throws {
        projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("SkillDeckProjectUpdate-\(UUID().uuidString)")
        sourceRoot = projectRoot.appendingPathComponent(".agents/skills")
        skillDirectory = sourceRoot.appendingPathComponent("demo")
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

        let service = ProjectSkillUpdateService(sourceRoot: sourceRoot)
        let skill = try await service.loadSkill(named: "demo", at: skillDirectory)

        XCTAssertEqual(skill.canonicalURL, skillDirectory)
        guard case .project(let scopedProjectURL) = skill.scope else {
            return XCTFail("Expected project skill scope")
        }
        XCTAssertEqual(scopedProjectURL.standardizedFileURL.path, projectRoot.standardizedFileURL.path)
        XCTAssertEqual(skill.lockEntry, expectedEntry)
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectLockURL.path))
    }
}
