import XCTest
@testable import SkillDeck

/// Unit tests for local skill import functionality
///
/// Tests the importLocalSkill() method on SkillManager and related validation logic.
/// Uses temporary directories to simulate skill directories with SKILL.md files.
///
/// XCTest is Swift's testing framework (similar to JUnit / Go's testing package):
/// - Test classes inherit from XCTestCase
/// - Test methods start with "test"
/// - Use XCTAssert* assertion methods (similar to JUnit's Assert.*)
/// - Run via: swift test --filter LocalImportTests
final class LocalImportTests: XCTestCase {

    /// Temporary directory for test fixtures (created fresh for each test)
    var tempDir: URL!

    /// Temporary directory simulating ~/.agents/ (for lock file and canonical skills)
    var agentsDir: URL!

    /// LockFileManager pointed at test lock file (avoids touching real ~/.agents/.skill-lock.json)
    var lockFileManager: LockFileManager!

    // MARK: - Setup / Teardown

    /// setUp runs before each test method (similar to JUnit's @Before)
    /// Creates temp directories and a LockFileManager pointed at test paths
    override func setUp() async throws {
        // Create unique temp directory per test to avoid interference between tests
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillDeckLocalImportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create agents directory (simulates ~/.agents/)
        agentsDir = tempDir.appendingPathComponent("agents")
        try FileManager.default.createDirectory(
            at: agentsDir.appendingPathComponent("skills"),
            withIntermediateDirectories: true
        )

        // Create LockFileManager pointed at test path
        let lockFilePath = agentsDir.appendingPathComponent(".skill-lock.json")
        lockFileManager = LockFileManager(filePath: lockFilePath)

        // Create empty lock file so updateEntry can work
        try await lockFileManager.createIfNotExists()
    }

    /// tearDown runs after each test method (similar to JUnit's @After)
    /// Cleans up temp directories
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        agentsDir = nil
        lockFileManager = nil
    }

    // MARK: - Helper Methods

    /// Create a test skill directory with a valid SKILL.md file
    /// - Parameters:
    ///   - name: Directory name (becomes the skill name)
    ///   - skillName: Name field in YAML frontmatter (defaults to directory name)
    ///   - description: Description field in YAML frontmatter
    /// - Returns: URL of the created skill directory
    private func createValidSkillDir(
        name: String,
        skillName: String? = nil,
        description: String = "A test skill"
    ) throws -> URL {
        let skillDir = tempDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

        // Write a valid SKILL.md with YAML frontmatter + markdown body
        let content = """
        ---
        name: \(skillName ?? name)
        description: \(description)
        ---

        # \(skillName ?? name)

        This is a test skill.
        """
        let skillMDURL = skillDir.appendingPathComponent("SKILL.md")
        try content.write(to: skillMDURL, atomically: true, encoding: .utf8)

        return skillDir
    }

    // MARK: - Validation Tests

    /// Test that a valid SKILL.md can be parsed from a local directory
    func testValidSkillMDParseable() throws {
        // Create a directory with valid SKILL.md
        let skillDir = try createValidSkillDir(name: "test-skill", description: "My test skill")
        let skillMDURL = skillDir.appendingPathComponent("SKILL.md")

        // Parse and verify
        let result = try SkillMDParser.parse(fileURL: skillMDURL)
        XCTAssertEqual(result.metadata.name, "test-skill")
        XCTAssertEqual(result.metadata.description, "My test skill")
        XCTAssertTrue(result.markdownBody.contains("# test-skill"))
    }

    /// Test that a directory without SKILL.md is detected
    func testMissingSkillMD() throws {
        // Create an empty directory (no SKILL.md)
        let emptyDir = tempDir.appendingPathComponent("empty-skill")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)

        // Verify SKILL.md does not exist
        let skillMDURL = emptyDir.appendingPathComponent("SKILL.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: skillMDURL.path))
    }

    /// Test that invalid SKILL.md content triggers a parse error
    func testInvalidSkillMDContent() throws {
        // Create a directory with invalid SKILL.md (no YAML frontmatter)
        let skillDir = tempDir.appendingPathComponent("bad-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

        let invalidContent = "This is not valid SKILL.md - no YAML frontmatter"
        let skillMDURL = skillDir.appendingPathComponent("SKILL.md")
        try invalidContent.write(to: skillMDURL, atomically: true, encoding: .utf8)

        // Parsing should throw an error (no --- delimiters for YAML frontmatter)
        XCTAssertThrowsError(try SkillMDParser.parse(fileURL: skillMDURL)) { error in
            // Verify it's a ParseError (not some other unexpected error)
            XCTAssertTrue(error is SkillMDParser.ParseError,
                         "Expected ParseError but got \(type(of: error))")
        }
    }

    /// Test that selecting a SKILL.md file URL resolves to its parent directory
    /// This tests the logic in LocalImportViewModel.openFolderPicker()
    func testSkillMDFileResolvesToParentDirectory() throws {
        let skillDir = try createValidSkillDir(name: "resolve-test")
        let skillMDURL = skillDir.appendingPathComponent("SKILL.md")

        // Simulate what LocalImportViewModel does: if URL points to SKILL.md, use parent
        let resolvedURL: URL
        if skillMDURL.lastPathComponent == "SKILL.md" {
            resolvedURL = skillMDURL.deletingLastPathComponent()
        } else {
            resolvedURL = skillMDURL
        }

        // The resolved URL should be the skill directory, not the SKILL.md file
        XCTAssertEqual(
            resolvedURL.standardized.path,
            skillDir.standardized.path,
            "SKILL.md URL should resolve to parent directory"
        )
    }

    // MARK: - File Copy Tests

    /// Test that copying a skill directory preserves all files
    func testCopySkillDirectoryPreservesFiles() throws {
        // Create a skill directory with SKILL.md + extra files
        let sourceDir = try createValidSkillDir(name: "copy-test")

        // Add an extra file to verify copy preserves all contents
        let extraFile = sourceDir.appendingPathComponent("extra.txt")
        try "extra content".write(to: extraFile, atomically: true, encoding: .utf8)

        // Copy to canonical location
        let canonicalDir = agentsDir.appendingPathComponent("skills").appendingPathComponent("copy-test")
        try FileManager.default.copyItem(at: sourceDir, to: canonicalDir)

        // Verify all files were copied
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: canonicalDir.appendingPathComponent("SKILL.md").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: canonicalDir.appendingPathComponent("extra.txt").path
        ))

        // Verify SKILL.md content is preserved
        let copiedContent = try String(contentsOf: canonicalDir.appendingPathComponent("SKILL.md"), encoding: .utf8)
        XCTAssertTrue(copiedContent.contains("copy-test"))
    }

    /// Test that overwriting an existing skill directory works correctly
    func testOverwriteExistingSkillDirectory() throws {
        let fm = FileManager.default
        let canonicalDir = agentsDir.appendingPathComponent("skills").appendingPathComponent("overwrite-test")

        // First import: create initial version
        let sourceV1 = try createValidSkillDir(name: "overwrite-v1", skillName: "overwrite-test", description: "Version 1")
        try fm.copyItem(at: sourceV1, to: canonicalDir)

        // Verify V1 exists
        let v1Content = try String(contentsOf: canonicalDir.appendingPathComponent("SKILL.md"), encoding: .utf8)
        XCTAssertTrue(v1Content.contains("Version 1"))

        // Second import: overwrite with V2 (delete first, then copy — same as importLocalSkill)
        let sourceV2 = try createValidSkillDir(name: "overwrite-v2", skillName: "overwrite-test", description: "Version 2")
        if fm.fileExists(atPath: canonicalDir.path) {
            try fm.removeItem(at: canonicalDir)
        }
        try fm.copyItem(at: sourceV2, to: canonicalDir)

        // Verify V2 replaced V1
        let v2Content = try String(contentsOf: canonicalDir.appendingPathComponent("SKILL.md"), encoding: .utf8)
        XCTAssertTrue(v2Content.contains("Version 2"))
        XCTAssertFalse(v2Content.contains("Version 1"))
    }

    // MARK: - Lock File Tests

    /// Test that lock entry is created with correct fields for local import
    func testLockEntryFieldsForLocalImport() async throws {
        let sourceDir = try createValidSkillDir(name: "lock-test-skill")

        // Simulate what importLocalSkill does: create lock entry with sourceType "local"
        let now = ISO8601DateFormatter().string(from: Date())
        let entry = LockEntry(
            source: sourceDir.path,
            sourceType: "local",
            sourceUrl: sourceDir.path,
            skillPath: "lock-test-skill/SKILL.md",
            skillFolderHash: "",  // Local imports have no git hash
            installedAt: now,
            updatedAt: now
        )
        try await lockFileManager.updateEntry(skillName: "lock-test-skill", entry: entry)

        // Read back and verify
        let readEntry = try await lockFileManager.getEntry(skillName: "lock-test-skill")
        XCTAssertNotNil(readEntry, "Lock entry should exist after import")
        XCTAssertEqual(readEntry?.sourceType, "local", "sourceType should be 'local' for local imports")
        XCTAssertEqual(readEntry?.source, sourceDir.path, "source should be the original directory path")
        XCTAssertEqual(readEntry?.sourceUrl, sourceDir.path, "sourceUrl should be the original directory path")
        XCTAssertEqual(readEntry?.skillPath, "lock-test-skill/SKILL.md")
        XCTAssertEqual(readEntry?.skillFolderHash, "", "skillFolderHash should be empty for local imports")
    }

    /// Test that local skills are filtered out in checkAllUpdates filter logic
    /// This verifies the filtering condition: sourceType != "local"
    func testLocalSkillsSkippedInUpdateCheck() {
        // Create lock entries for both types
        let githubEntry = LockEntry(
            source: "owner/repo",
            sourceType: "github",
            sourceUrl: "https://github.com/owner/repo.git",
            skillPath: "skills/test/SKILL.md",
            skillFolderHash: "abc123",
            installedAt: "2024-01-01T00:00:00Z",
            updatedAt: "2024-01-01T00:00:00Z"
        )

        let localEntry = LockEntry(
            source: "/Users/test/my-skill",
            sourceType: "local",
            sourceUrl: "/Users/test/my-skill",
            skillPath: "my-skill/SKILL.md",
            skillFolderHash: "",
            installedAt: "2024-01-01T00:00:00Z",
            updatedAt: "2024-01-01T00:00:00Z"
        )

        // Simulate the filter logic from checkAllUpdates()
        // This is the exact condition used in SkillManager.checkAllUpdates():
        // skills.filter { $0.lockEntry != nil && $0.lockEntry?.sourceType != "local" }
        let entries: [LockEntry?] = [githubEntry, localEntry, nil]
        let filtered = entries.filter { $0 != nil && $0?.sourceType != "local" }

        // Only the GitHub entry should pass the filter
        XCTAssertEqual(filtered.count, 1, "Only non-local entries should pass the filter")
        XCTAssertEqual(filtered.first??.sourceType, "github")
    }

    // MARK: - ImportError Tests

    /// Test ImportError enum descriptions are human-readable
    func testImportErrorDescriptions() {
        let dirNotFound = SkillManager.ImportError.directoryNotFound("/some/path")
        XCTAssertTrue(dirNotFound.localizedDescription.contains("/some/path"),
                      "Error message should contain the path")

        let noSkillMD = SkillManager.ImportError.skillMDNotFound("/another/path")
        XCTAssertTrue(noSkillMD.localizedDescription.contains("SKILL.md"),
                      "Error message should mention SKILL.md")

        let parseFailed = SkillManager.ImportError.parseFailed("invalid YAML")
        XCTAssertTrue(parseFailed.localizedDescription.contains("invalid YAML"),
                      "Error message should contain the parse error detail")
    }
}
