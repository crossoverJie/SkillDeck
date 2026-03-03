import Foundation

/// RepositoryManager manages user-configured custom Git repositories as Skills sources.
///
/// Responsibilities:
/// - Persist repository configurations to `~/.agents/.skilldeck-repos.json`
/// - Clone new repositories to `~/.agents/repos/<slug>/`
/// - Pull updates for already-cloned repositories
/// - Scan cloned repositories to discover available Skills
///
/// Uses `actor` for thread safety — file I/O and git operations run on a background thread,
/// and actor ensures only one operation executes at a time (no data races).
/// This is the same pattern used by LockFileManager and GitService.
actor RepositoryManager {

    // MARK: - Error Types

    enum RepositoryError: Error, LocalizedError {
        case invalidURL(String)
        case cloneFailed(String)
        case alreadyExists(String)
        case notFound(UUID)
        case missingCredentials(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL(let url):
                "Invalid repository URL: \(url)"
            case .cloneFailed(let msg):
                "Failed to clone repository: \(msg)"
            case .alreadyExists(let slug):
                "A repository with local path '\(slug)' already exists"
            case .notFound(let id):
                "Repository with id \(id) not found"
            case .missingCredentials(let reason):
                reason
            }
        }
    }

    // MARK: - Persisted Config

    /// Top-level wrapper for JSON serialization.
    /// Versioned so we can migrate the schema in the future.
    private struct RepoConfig: Codable {
        var version: Int = 1
        var repositories: [SkillRepository] = []
    }

    // MARK: - Private State

    /// Cached in-memory list of repositories (mirrors what's on disk)
    private var cachedRepos: [SkillRepository] = []

    /// Whether the config has been loaded from disk at least once
    private var isLoaded = false

    /// Shared GitService instance for clone/pull operations
    private let gitService = GitService()

    // MARK: - Config File Path

    /// Expanded absolute path to the config file
    private var configFilePath: String {
        NSString(string: Constants.skillReposConfigPath).expandingTildeInPath
    }

    /// Expanded absolute path to the repos base directory
    private var reposBasePath: String {
        NSString(string: Constants.reposBasePath).expandingTildeInPath
    }

    // MARK: - Public API

    /// Load and return all configured repositories from disk.
    ///
    /// On first call, reads from `~/.agents/.skilldeck-repos.json`.
    /// Subsequent calls return the in-memory cache (no re-read from disk).
    func loadAll() async -> [SkillRepository] {
        if !isLoaded {
            await loadFromDisk()
        }
        return cachedRepos
    }

    /// Add a new repository configuration and persist it to disk.
    ///
    /// - Parameter repo: The repository to add (id and localSlug must be unique)
    /// - Throws: RepositoryError.alreadyExists if a repo with the same slug already exists
    func add(_ repo: SkillRepository) async throws {
        if !isLoaded { await loadFromDisk() }

        // Prevent duplicate slugs (same remote repo added twice)
        if cachedRepos.contains(where: { $0.localSlug == repo.localSlug }) {
            throw RepositoryError.alreadyExists(repo.localSlug)
        }

        cachedRepos.append(repo)
        await saveToDisk()
    }

    /// Remove a repository configuration by ID and persist the change.
    ///
    /// Note: This does NOT delete the cloned directory from disk.
    /// The local clone is left intact so users don't accidentally lose data.
    func remove(id: UUID) async {
        if !isLoaded { await loadFromDisk() }
        let removed = cachedRepos.filter { $0.id == id }
        cachedRepos.removeAll { $0.id == id }
        for repo in removed {
            if let key = repo.credentialKey {
                RepositoryCredentialStore.deleteToken(for: key)
            }
        }
        await saveToDisk()
    }

    /// Update an existing repository's configuration (e.g. renamed by user).
    func update(_ repo: SkillRepository) async {
        if !isLoaded { await loadFromDisk() }
        if let idx = cachedRepos.firstIndex(where: { $0.id == repo.id }) {
            cachedRepos[idx] = repo
            await saveToDisk()
        }
    }

    /// Sync all enabled repositories: clone if not yet cloned, pull otherwise.
    ///
    /// Runs each repository's sync sequentially to avoid hitting git's SSH connection limits.
    /// Errors are logged per-repository and do not stop other repos from syncing.
    ///
    /// - Returns: Dictionary of sync results keyed by repo ID (nil value = success, String = error message)
    @discardableResult
    func syncAll() async -> [UUID: String?] {
        if !isLoaded { await loadFromDisk() }

        var results: [UUID: String?] = [:]
        for repo in cachedRepos where repo.isEnabled {
            do {
                try await sync(repo: repo)
                results[repo.id] = nil  // nil = success
            } catch {
                results[repo.id] = error.localizedDescription
            }
        }
        return results
    }

    /// Sync a single repository: clone if not yet cloned, pull if already cloned.
    ///
    /// After a successful sync, updates `lastSyncedAt` in the persisted config.
    ///
    /// - Parameter repo: The repository to sync
    /// - Throws: RepositoryError.cloneFailed or GitService.GitError
    func sync(repo: SkillRepository) async throws {
        if !isLoaded { await loadFromDisk() }

        // Ensure the base repos directory exists
        try createReposDirectoryIfNeeded()

        let httpAuthorization = try httpAuthorization(for: repo)

        let repoDir = URL(fileURLWithPath: repo.localPath)

        if repo.isCloned {
            // Repository already cloned — pull latest changes
            try await gitService.pull(repoDir: repoDir, httpAuthorization: httpAuthorization)
        } else {
            // First time — clone the repository
            // We clone directly into the target path (not a temp dir) since this is a persistent clone.
            // Git requires the target directory to NOT exist, so we just pass the final path.
            try await cloneDirectly(repo: repo, httpAuthorization: httpAuthorization)
        }

        // Update lastSyncedAt timestamp in persisted config
        if let idx = cachedRepos.firstIndex(where: { $0.id == repo.id }) {
            cachedRepos[idx].lastSyncedAt = Date()
            await saveToDisk()
        }
    }

    /// Scan a cloned repository for available Skills.
    ///
    /// Reuses `GitService.scanSkillsInRepo` which recursively walks the repo
    /// directory and parses all SKILL.md files it finds.
    ///
    /// Marked `async` because `gitService.scanSkillsInRepo` is an actor-isolated method —
    /// calling it from outside the `GitService` actor requires `await` (cross-actor async hop).
    ///
    /// - Parameter repo: The repository to scan (must be cloned locally)
    /// - Returns: Array of discovered skills (empty if repo is not cloned)
    func scanSkills(in repo: SkillRepository) async -> [GitService.DiscoveredSkill] {
        guard repo.isCloned else { return [] }
        let repoDir = URL(fileURLWithPath: repo.localPath)
        return await gitService.scanSkillsInRepo(repoDir: repoDir)
    }

    // MARK: - Private: Clone

    /// Clone a repository into its permanent location via GitService.
    ///
    /// **Why not call Process directly here?**
    /// `RepositoryManager` is a Swift `actor`. Calling `process.waitUntilExit()` (a
    /// synchronous blocking call) inside an actor would hold the actor's thread,
    /// preventing ALL other actor methods (including `scanSkills`) from running until
    /// the clone finishes. This causes the "Scanning repository…" spinner to hang
    /// because `scanSkills` is queued behind the blocking clone.
    ///
    /// **Solution**: delegate to `gitService.cloneRepo()`.
    /// Because `GitService` is a separate actor, `await gitService.cloneRepo(…)`
    /// *suspends* this actor's task and releases its thread — so `scanSkills` and
    /// other methods can run concurrently while git is cloning in the GitService actor.
    /// After cloning, we move the temp directory to the permanent `~/.agents/repos/<slug>/` path.
    private func cloneDirectly(repo: SkillRepository, httpAuthorization: String?) async throws {
        // Full clone (not shallow) so `git pull` works later.
        // gitService.cloneRepo clones to /tmp/SkillDeck-<UUID>/ first.
        // The `await` suspends RepositoryManager (releases the actor), allowing
        // scanSkills() and other calls to proceed while git is running.
        let tempDir = try await gitService.cloneRepo(
            repoURL: repo.repoURL,
            shallow: false,
            httpAuthorization: httpAuthorization
        )

        let targetURL = URL(fileURLWithPath: repo.localPath)

        // If a previous partial clone left a directory behind, remove it first
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }

        // Move the temp clone to its permanent location atomically
        // (FileManager.moveItem is rename(2) when on the same filesystem as /tmp)
        do {
            try FileManager.default.moveItem(at: tempDir, to: targetURL)
        } catch {
            // Clean up temp dir if move fails
            try? FileManager.default.removeItem(at: tempDir)
            throw RepositoryError.cloneFailed("Failed to move cloned repository: \(error.localizedDescription)")
        }
    }

    private func httpAuthorization(for repo: SkillRepository) throws -> String? {
        guard repo.authType == .httpsToken else { return nil }

        guard let key = repo.credentialKey, !key.isEmpty else {
            throw RepositoryError.missingCredentials("Missing HTTPS token key for repository '\(repo.name)'")
        }
        guard let token = RepositoryCredentialStore.getToken(for: key), !token.isEmpty else {
            throw RepositoryError.missingCredentials("No access token found for repository '\(repo.name)'. Please reconfigure token in Settings.")
        }

        let trimmedUser = repo.httpUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let username = trimmedUser.isEmpty ? "git" : trimmedUser
        let raw = "\(username):\(token)"
        let basic = Data(raw.utf8).base64EncodedString()
        return "Authorization: Basic \(basic)"
    }

    // MARK: - Private: Persistence

    /// Read the config file from disk and populate cachedRepos.
    /// If the file doesn't exist yet, starts with an empty list.
    private func loadFromDisk() async {
        isLoaded = true
        let path = configFilePath

        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            cachedRepos = []
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let config = try decoder.decode(RepoConfig.self, from: data)
            cachedRepos = config.repositories
        } catch {
            // Malformed config — reset to empty rather than crashing
            cachedRepos = []
        }
    }

    /// Write cachedRepos to disk atomically.
    ///
    /// Atomic write: write to a temp file first, then rename,
    /// so a crash mid-write doesn't corrupt the config.
    private func saveToDisk() async {
        let config = RepoConfig(version: 1, repositories: cachedRepos)

        do {
            let encoder = JSONEncoder()
            // Pretty-print for human readability (config is small, no perf concern)
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(config)

            let path = configFilePath

            // Ensure parent directory exists
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: dir,
                withIntermediateDirectories: true,
                attributes: nil
            )

            // Atomic write via temp file + rename
            let tempPath = path + ".tmp"
            FileManager.default.createFile(atPath: tempPath, contents: data)
            let targetURL = URL(fileURLWithPath: path)
            let tempURL = URL(fileURLWithPath: tempPath)

            if FileManager.default.fileExists(atPath: path) {
                // Existing file: replace atomically.
                _ = try FileManager.default.replaceItemAt(
                    targetURL,
                    withItemAt: tempURL
                )
            } else {
                // First write: move temp file to final path.
                try FileManager.default.moveItem(at: tempURL, to: targetURL)
            }
        } catch {
            // Non-fatal: log but don't crash; the in-memory state remains consistent
        }
    }

    /// Ensure ~/.agents/repos/ directory exists.
    private func createReposDirectoryIfNeeded() throws {
        try FileManager.default.createDirectory(
            atPath: reposBasePath,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

}
