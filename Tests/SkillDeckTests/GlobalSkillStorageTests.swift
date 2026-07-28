import XCTest
@testable import SkillDeck

/// Tests the configured canonical storage contract used by scanning, installation and global sync.
final class GlobalSkillStorageTests: XCTestCase {
    func testConfiguredDirectoryDrivesCanonicalFiles() {
        let originalPath = SkillStorageSettings.globalSkillsPath
        let configuredURL = FileManager.default.temporaryDirectory.appendingPathComponent("SkillDeckConfiguredSkills-\(UUID().uuidString)")
        defer { SkillStorageSettings.setGlobalSkillsPath(originalPath) }

        SkillStorageSettings.setGlobalSkillsPath(configuredURL.path)

        XCTAssertEqual(SkillStorageSettings.globalSkillsURL.path, configuredURL.path)
        XCTAssertEqual(SkillScanner.sharedSkillsURL.path, configuredURL.path)
        XCTAssertEqual(LockFileManager.defaultPath.path, configuredURL.deletingLastPathComponent().appendingPathComponent(".skill-lock.json").path)
        XCTAssertEqual(CommitHashCache.defaultPath.path, configuredURL.deletingLastPathComponent().appendingPathComponent(".skilldeck-cache.json").path)
    }

    func testGlobalManagedProjectUsesConfiguredDirectory() {
        let originalPath = SkillStorageSettings.globalSkillsPath
        let configuredURL = FileManager.default.temporaryDirectory.appendingPathComponent("SkillDeckConfiguredGlobal-\(UUID().uuidString)")
        defer { SkillStorageSettings.setGlobalSkillsPath(originalPath) }

        SkillStorageSettings.setGlobalSkillsPath(configuredURL.path)
        let globalProject = ManagedProject(rootPath: NSHomeDirectory(), displayName: "全局技能", usesConfiguredGlobalSource: true)

        XCTAssertEqual(globalProject.sourceSkillsURL.path, configuredURL.path)
    }

    func testGlobalSyncTargetsMatchSidebarAgents() {
        XCTAssertEqual(ProjectAgent.global.map(\.id), AgentType.allCases.map(\.id))
        XCTAssertEqual(ProjectAgent.global.map(\.name), AgentType.allCases.map(\.displayName))
    }
}
