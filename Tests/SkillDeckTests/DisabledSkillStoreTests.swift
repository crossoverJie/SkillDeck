import XCTest
@testable import SkillDeck

/// Covers the reversible archive independently from global or project scanner state.
final class DisabledSkillStoreTests: XCTestCase {
    private var root: URL!
    private var sourceSkill: URL!
    private var archiveRoot: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SkillDeckDisabled-\(UUID().uuidString)")
        sourceSkill = root.appendingPathComponent("skills/demo")
        archiveRoot = root.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at: sourceSkill, withIntermediateDirectories: true)
        try "---\nname: Demo\n---\n".write(to: sourceSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testDisableAndRestorePreservesOriginalDirectory() throws {
        let skill = Skill(
            id: "demo",
            canonicalURL: sourceSkill,
            metadata: SkillMetadata(name: "Demo", description: "Test", license: nil, metadata: nil, allowedTools: nil),
            markdownBody: "",
            scope: .sharedGlobal,
            installations: [],
            lockEntry: nil
        )
        let store = DisabledSkillStore(root: archiveRoot)

        let record = try store.disable(skill: skill)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceSkill.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: record.archivedPath).appendingPathComponent("SKILL.md").path))
        XCTAssertEqual(try store.records(), [record])

        try store.restore(record)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceSkill.appendingPathComponent("SKILL.md").path))
        XCTAssertTrue(try store.records().isEmpty)
    }
}
