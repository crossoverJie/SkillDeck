import Foundation

/// DisabledSkillRecord persists the original location for one skill moved out of its active source.
/// Keeping this record under the user's shared `.agents` directory avoids modifying a project worktree
/// and lets the app restore the directory after a branch switch or app restart.
struct DisabledSkillRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let displayName: String
    let originalPath: String
    let archivedPath: String
    let scopeLabel: String
    let projectName: String?
    let disabledAt: Date
}

/// DisabledSkillStore provides reversible skill disablement outside any project repository.
/// FileManager.moveItem preserves every file in the skill directory and is reversible by moving the
/// same directory back, unlike a delete operation which permanently removes the skill contents.
struct DisabledSkillStore {
    private struct ArchiveIndex: Codable {
        var records: [DisabledSkillRecord]
    }

    /// The shared archive deliberately lives under the home-level `.agents` directory rather than a
    /// project `.agents` directory, so it is not tracked, ignored, or removed by project branch changes.
    static var defaultRoot: URL {
        URL(fileURLWithPath: NSString(string: "~/.agents/.skilldeck-disabled").expandingTildeInPath)
    }

    private let root: URL
    private let fileManager: FileManager

    init(root: URL = DisabledSkillStore.defaultRoot, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
    }

    /// Moves an active skill directory into the central archive and records the exact restore path.
    func disable(skill: Skill, projectName: String? = nil) throws -> DisabledSkillRecord {
        try fileManager.createDirectory(at: entriesURL, withIntermediateDirectories: true)
        let id = UUID()
        let archiveURL = entriesURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.moveItem(at: skill.canonicalURL, to: archiveURL)

        let record = DisabledSkillRecord(
            id: id,
            displayName: skill.displayName,
            originalPath: skill.canonicalURL.path,
            archivedPath: archiveURL.path,
            scopeLabel: skill.scope.displayName,
            projectName: projectName,
            disabledAt: Date()
        )
        var index = try readIndex()
        index.records.append(record)
        try writeIndex(index)
        return record
    }

    /// Restores a disabled directory to its recorded original path. Existing active content is never
    /// overwritten because it could be a newer skill created while the archived one was disabled.
    func restore(_ record: DisabledSkillRecord) throws {
        let originalURL = URL(fileURLWithPath: record.originalPath)
        guard !fileManager.fileExists(atPath: originalURL.path) else {
            throw DisabledSkillStoreError.restoreDestinationExists(originalURL.path)
        }
        try fileManager.createDirectory(at: originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: URL(fileURLWithPath: record.archivedPath), to: originalURL)

        var index = try readIndex()
        index.records.removeAll { $0.id == record.id }
        try writeIndex(index)
    }

    func records() throws -> [DisabledSkillRecord] {
        try readIndex().records.sorted { $0.disabledAt > $1.disabledAt }
    }

    private var entriesURL: URL { root.appendingPathComponent("entries", isDirectory: true) }
    private var indexURL: URL { root.appendingPathComponent("index.json") }

    private func readIndex() throws -> ArchiveIndex {
        guard fileManager.fileExists(atPath: indexURL.path) else { return ArchiveIndex(records: []) }
        return try JSONDecoder().decode(ArchiveIndex.self, from: Data(contentsOf: indexURL))
    }

    private func writeIndex(_ index: ArchiveIndex) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(index).write(to: indexURL, options: .atomic)
    }
}

enum DisabledSkillStoreError: LocalizedError {
    case restoreDestinationExists(String)

    var errorDescription: String? {
        switch self {
        case .restoreDestinationExists(let path):
            return L10n.currentFormat(L10nKeys.dashboardRestoreConflict, path)
        }
    }
}
