import Foundation

/// ProjectSkillUpdateService owns repository metadata for one project's `.agents/skills` directory.
/// It deliberately uses a project-local lock file so update operations cannot overwrite a global skill
/// with the same folder name.
actor ProjectSkillUpdateService {
    struct UpdateCheck: Equatable {
        let hasUpdate: Bool
        let remoteHash: String
    }

    private let sourceRoot: URL
    private let lockFileManager: LockFileManager
    private let gitService = GitService()

    init(sourceRoot: URL) {
        self.sourceRoot = sourceRoot
        let agentsRoot = sourceRoot.deletingLastPathComponent()
        self.lockFileManager = LockFileManager(filePath: agentsRoot.appendingPathComponent(".skill-lock.json"))
    }

    /// Loads a project skill together with its project-local repository metadata.
    func loadSkill(named name: String, at directory: URL) async throws -> Skill {
        let parsed = try SkillMDParser.parse(fileURL: directory.appendingPathComponent("SKILL.md"))
        let entry = await lockEntry(for: name)
        return Skill(
            id: name,
            canonicalURL: directory,
            metadata: parsed.metadata,
            markdownBody: parsed.markdownBody,
            scope: .project(sourceRoot.deletingLastPathComponent().deletingLastPathComponent()),
            installations: [],
            lockEntry: entry
        )
    }

    /// Associates a project skill with a GitHub repository and records a project-local baseline.
    func link(skill: Skill, repositoryInput: String) async throws -> Skill {
        let (repositoryURL, source) = try GitService.normalizeRepoURL(repositoryInput)
        let repository = try await gitService.shallowClone(repoURL: repositoryURL)
        defer { Task { await gitService.cleanupTempDirectory(repository) } }

        let discovered = await gitService.scanSkillsInRepo(repoDir: repository, repoURL: repositoryURL)
        guard let remoteSkill = discovered.first(where: { $0.id == skill.id }) else {
            throw ProjectSkillUpdateError.skillNotFoundInRepository(skill.id)
        }

        let treeHash = try await gitService.getTreeHash(for: remoteSkill.folderPath, in: repository)
        try replaceLocalSkill(at: skill.canonicalURL, from: sourceDirectory(for: remoteSkill.folderPath, in: repository))

        let now = ISO8601DateFormatter().string(from: Date())
        let entry = LockEntry(
            source: source,
            sourceType: "github",
            sourceUrl: repositoryURL,
            skillPath: remoteSkill.skillMDPath,
            skillFolderHash: treeHash,
            installedAt: now,
            updatedAt: now
        )
        try await lockFileManager.createIfNotExists()
        try await lockFileManager.updateEntry(skillName: skill.id, entry: entry)
        return try await loadSkill(named: skill.id, at: skill.canonicalURL)
    }

    /// Checks the project's stored Git baseline against the latest remote folder tree.
    func checkForUpdate(skill: Skill) async throws -> UpdateCheck {
        guard let entry = skill.lockEntry, entry.sourceType == "github" else {
            throw ProjectSkillUpdateError.repositoryNotLinked
        }
        let repository = try await gitService.shallowClone(repoURL: entry.sourceUrl)
        defer { Task { await gitService.cleanupTempDirectory(repository) } }

        let remoteHash = try await gitService.getTreeHash(for: folderPath(from: entry.skillPath), in: repository)
        return UpdateCheck(hasUpdate: remoteHash != entry.skillFolderHash, remoteHash: remoteHash)
    }

    /// Replaces only the selected project skill directory and advances its project-local lock entry.
    func update(skill: Skill, remoteHash: String) async throws -> Skill {
        guard var entry = skill.lockEntry, entry.sourceType == "github" else {
            throw ProjectSkillUpdateError.repositoryNotLinked
        }
        let repository = try await gitService.shallowClone(repoURL: entry.sourceUrl)
        defer { Task { await gitService.cleanupTempDirectory(repository) } }

        try replaceLocalSkill(at: skill.canonicalURL, from: sourceDirectory(for: folderPath(from: entry.skillPath), in: repository))
        entry.skillFolderHash = remoteHash
        entry.updatedAt = ISO8601DateFormatter().string(from: Date())
        try await lockFileManager.updateEntry(skillName: skill.id, entry: entry)
        return try await loadSkill(named: skill.id, at: skill.canonicalURL)
    }

    /// Deletes only this project's source skill directory and its project-local lock entry.
    /// The service owns `sourceRoot`, so a dashboard action cannot remove a same-named global skill.
    func deleteSkill(named name: String) async throws {
        let directory = sourceRoot.appendingPathComponent(name)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        if await lockFileManager.exists {
            try await lockFileManager.removeEntry(skillName: name)
        }
    }

    private func lockEntry(for skillName: String) async -> LockEntry? {
        await lockFileManager.invalidateCache()
        guard await lockFileManager.exists else { return nil }
        return try? await lockFileManager.getEntry(skillName: skillName)
    }

    private func sourceDirectory(for folderPath: String, in repository: URL) -> URL {
        folderPath.isEmpty ? repository : repository.appendingPathComponent(folderPath)
    }

    private func folderPath(from skillPath: String) -> String {
        if skillPath == "SKILL.md" { return "" }
        if skillPath.hasSuffix("/SKILL.md") {
            return String(skillPath.dropLast("/SKILL.md".count))
        }
        return skillPath
    }

    private func replaceLocalSkill(at destination: URL, from source: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: destination)
    }
}

enum ProjectSkillUpdateError: LocalizedError {
    case repositoryNotLinked
    case skillNotFoundInRepository(String)

    var errorDescription: String? {
        switch self {
        case .repositoryNotLinked:
            return "请先关联 GitHub 仓库"
        case .skillNotFoundInRepository(let name):
            return "仓库中未找到技能：\(name)"
        }
    }
}
