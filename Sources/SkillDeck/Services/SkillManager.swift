import Foundation
import Combine

/// SkillManager is the core orchestrator for skill management (Orchestrator pattern)
///
/// It composes all sub-services (Scanner, Parser, LockFileManager, SymlinkManager, FileSystemWatcher),
/// providing a unified CRUD interface to the outside.
///
/// @Observable is a macro introduced in macOS 14+, replacing the older ObservableObject protocol.
/// When properties of an @Observable-marked class change, SwiftUI automatically refreshes related Views.
/// Similar to Android Jetpack's LiveData or Vue.js reactive data.
///
/// @MainActor marks that all methods of this class execute on the main thread,
/// as it holds UI state (skills, agents arrays), and UI updates must be on the main thread.
/// Similar to Android's @UiThread annotation.
@MainActor
@Observable
final class SkillManager {

    // MARK: - Error Types

    /// Error types for manually linking repositories
    /// LocalizedError protocol provides human-readable error descriptions (similar to Java's getMessage())
    enum LinkError: Error, LocalizedError {
        /// No matching skill directory found in repository
        case skillNotFoundInRepo(String)
        /// Git operation failed
        case gitError(String)

        var errorDescription: String? {
            switch self {
            case .skillNotFoundInRepo(let name):
                "Skill '\(name)' not found in repository"
            case .gitError(let message):
                message
            }
        }
    }

    // MARK: - Published State (UI-bound state)

    /// All discovered skills (deduplicated)
    var skills: [Skill] = []

    /// All detected Agents
    var agents: [Agent] = []

    /// Whether data is currently loading
    var isLoading = false

    /// Most recent error message
    var errorMessage: String?

    /// F12: Whether batch update checking is in progress (shows global progress)
    var isCheckingUpdates = false

    /// F12: Update status (indexed by skill id, persists across refreshes)
    /// Stores update check status for each skill (5 states), keyed by skill.id
    /// Changed type from [String: Bool] to [String: SkillUpdateStatus] for richer UI feedback
    var updateStatuses: [String: SkillUpdateStatus] = [:]

    // MARK: - App Update State (application self-update status)

    /// Latest release info (nil means no update available or not yet checked)
    /// Multiple Views need access (Settings About page, SidebarView toolbar reminder icon),
    /// so it's placed in global SkillManager rather than ViewModel
    var appUpdateInfo: AppUpdateInfo?

    /// Whether app update check is in progress (shows loading indicator)
    var isCheckingAppUpdate = false

    /// Whether update download is in progress (shows progress bar)
    var isDownloadingUpdate = false

    /// Download progress (0.0 ~ 1.0), used for progress bar display
    var downloadProgress: Double = 0

    /// Error message during update process (displayed to user, retryable)
    var updateError: String?

    // MARK: - Dependencies (dependent sub-services)

    private let scanner = SkillScanner()
    private let detector = AgentDetector()
    private let lockFileManager = LockFileManager()
    private let watcher = FileSystemWatcher()
    /// Application self-update checker (GitHub Release check, download, install)
    private let updateChecker = UpdateChecker()
    /// F10/F12: Git operations service for installation and update checking
    private let gitService = GitService()
    /// F12: SkillDeck private commit hash cache, independent of .skill-lock.json
    /// Stored in ~/.agents/.skilldeck-cache.json, doesn't pollute npx skills' lock file format
    private let commitHashCache = CommitHashCache()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupFileWatcher()
    }

    /// Set up file system monitoring
    /// Automatically triggers refresh when file system changes
    private func setupFileWatcher() {
        // sink is the subscription method of Combine framework (similar to RxJava's subscribe)
        // When watcher.onChange emits an event, execute the code in the closure
        watcher.onChange
            .sink { [weak self] in
                // Task { } creates an asynchronous task (similar to Go's go func(){})
                Task { await self?.refresh() }
            }
            .store(in: &cancellables)  // Save subscription to prevent premature release
    }

    // MARK: - Core Operations

    /// Refresh all data: re-detect Agents and scan skills
    func refresh() async {
        isLoading = true
        errorMessage = nil

        do {
            // Execute Agent detection and Skill scanning concurrently
            // async let is similar to Go's goroutine + channel, both tasks run in parallel
            async let detectedAgents = detector.detectAll()
            async let scannedSkills = scanner.scanAll()

            agents = await detectedAgents
            var allSkills = try await scannedSkills

            // Populate lock file information
            if await lockFileManager.exists {
                if let lockFile = try? await lockFileManager.read() {
                    for i in allSkills.indices {
                        allSkills[i].lockEntry = lockFile.skills[allSkills[i].id]
                    }
                }
            }

            // Synthesize LockEntry for skills without lockEntry but with manual link info
            // So these skills can reuse existing update check flows (checkForUpdate, checkAllUpdates)
            let linkedInfos = await commitHashCache.getAllLinkedInfos()
            for i in allSkills.indices {
                if allSkills[i].lockEntry == nil, let linked = linkedInfos[allSkills[i].id] {
                    // Synthesize LockEntry: fields aligned with LinkedSkillInfo
                    // installedAt/updatedAt use link time (for UI display only)
                    allSkills[i].lockEntry = LockEntry(
                        source: linked.source,
                        sourceType: linked.sourceType,
                        sourceUrl: linked.sourceUrl,
                        skillPath: linked.skillPath,
                        skillFolderHash: linked.skillFolderHash,
                        installedAt: linked.linkedAt,
                        updatedAt: linked.linkedAt
                    )
                }
            }

            skills = allSkills

            // F12: Restore previous update status (refresh should not clear update check results)
            // Also load local commit hash from CommitHashCache
            // Restore hasUpdate boolean from SkillUpdateStatus enum: only .hasUpdate counts as having an update
            for i in skills.indices {
                if let status = updateStatuses[skills[i].id] {
                    skills[i].hasUpdate = (status == .hasUpdate)
                }
                // Read local commit hash from CommitHashCache
                // Used for displaying hash comparison in UI and generating GitHub compare URL
                skills[i].localCommitHash = await commitHashCache.getHash(for: skills[i].id)
            }

            // Start file system monitoring
            startWatching()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Start watching file system, monitor all relevant directories
    private func startWatching() {
        var paths: [URL] = [SkillScanner.sharedSkillsURL]
        for agent in AgentType.allCases where agent != .codex {
            paths.append(agent.skillsDirectoryURL)
        }
        watcher.startWatching(paths: paths)
    }

    // MARK: - F04: Skill Deletion

    /// Delete a skill
    ///
    /// Deletion flow:
    /// 1. Remove direct installation symlinks from all Agents (skip inherited installations)
    /// 2. Delete canonical directory (actual files)
    /// 3. Update lock file
    /// 4. Refresh data
    ///
    /// Inherited installation symlinks don't need separate deletion: they point to symlinks in the source Agent directory,
    /// and the source Agent's symlink will be deleted in step 1; even if not deleted, after the canonical directory is removed
    /// they become dangling symlinks, which don't affect functionality
    func deleteSkill(_ skill: Skill) async throws {
        // 1. Remove all direct installation symlinks (skip inherited installations)
        for installation in skill.installations where installation.isSymlink && !installation.isInherited {
            try SymlinkManager.removeSymlink(
                skillName: skill.id,
                from: installation.agentType
            )
        }

        // 2. Delete canonical directory
        let fm = FileManager.default
        if fm.fileExists(atPath: skill.canonicalURL.path) {
            try fm.removeItem(at: skill.canonicalURL)
        }

        // 3. Update lock file (if there's a record)
        if skill.lockEntry != nil {
            try await lockFileManager.removeEntry(skillName: skill.id)
        }

        // 4. Refresh list
        await refresh()
    }

    // MARK: - F05: Save Edited Skill

    /// Save edited skill (update SKILL.md)
    func saveSkill(_ skill: Skill, metadata: SkillMetadata, markdownBody: String) async throws {
        let content = try SkillMDParser.serialize(metadata: metadata, markdownBody: markdownBody)
        let skillMDURL = skill.canonicalURL.appendingPathComponent("SKILL.md")
        try content.write(to: skillMDURL, atomically: true, encoding: .utf8)
        await refresh()
    }

    // MARK: - F06: Agent Assignment (Toggle Symlink)

    /// Install skill to specified Agent (create symlink)
    func assignSkill(_ skill: Skill, to agent: AgentType) async throws {
        try SymlinkManager.createSymlink(from: skill.canonicalURL, to: agent)
        await refresh()
    }

    /// Uninstall skill from specified Agent (delete symlink)
    func unassignSkill(_ skill: Skill, from agent: AgentType) async throws {
        try SymlinkManager.removeSymlink(skillName: skill.id, from: agent)
        await refresh()
    }

    /// Toggle skill installation status on specified Agent
    ///
    /// Protection logic: if inherited installation (isInherited), return directly without any operation
    /// This is Service layer defense - even if UI layer disables Toggle, it ensures inherited installations won't be mistakenly operated
    func toggleAssignment(_ skill: Skill, agent: AgentType) async throws {
        let installation = skill.installations.first { $0.agentType == agent }

        // Protection: inherited installations cannot be toggled (inherited installations are managed by source Agent)
        if let installation, installation.isInherited {
            return
        }

        // Protection: Codex canonical installation cannot be toggled
        // Codex's skills directory is the same as the canonical shared directory (~/.agents/skills/),
        // its installation record has isSymlink = false, indicating it's the original file not a symlink.
        // Deleting canonical files should use deleteSkill, not through toggle operation
        if agent == .codex, let installation, !installation.isSymlink {
            return
        }

        let isInstalled = installation != nil
        if isInstalled {
            try await unassignSkill(skill, from: agent)
        } else {
            try await assignSkill(skill, to: agent)
        }
    }

    // MARK: - F10: One-Click Install

    /// Install skill from cloned repository to local
    ///
    /// Installation flow:
    /// 1. Get tree hash (for lock file recording, subsequent update detection)
    /// 2. Copy files to canonical directory (~/.agents/skills/<name>/)
    /// 3. Create symlinks for selected Agents (skip Codex as it shares canonical directory)
    /// 4. Create/update lock file entry
    /// 5. Refresh UI
    ///
    /// - Parameters:
    ///   - repoDir: Local temporary directory of cloned repository
    ///   - skill: Skill info to install (from GitService.scanSkillsInRepo)
    ///   - repoSource: Repository source identifier (e.g. "vercel-labs/skills", for lock file)
    ///   - repoURL: Full repository URL (e.g. "https://github.com/vercel-labs/skills.git")
    ///   - targetAgents: Set of Agents to install to
    func installSkill(
        from repoDir: URL,
        skill: GitService.DiscoveredSkill,
        repoSource: String,
        repoURL: String,
        targetAgents: Set<AgentType>
    ) async throws {
        let fm = FileManager.default

        // 1. Get tree hash (git rev-parse HEAD:<folderPath>)
        let treeHash = try await gitService.getTreeHash(for: skill.folderPath, in: repoDir)

        // 1.5 Get commit hash and write to CommitHashCache (independent of lock file)
        // commit hash is used for generating GitHub compare URL later, showing update differences
        let commitHash = try await gitService.getCommitHash(in: repoDir)
        await commitHashCache.setHash(for: skill.id, hash: commitHash)
        try await commitHashCache.save()

        // 2. Copy to canonical directory
        // canonical path: ~/.agents/skills/<skillName>/
        let canonicalDir = SkillScanner.sharedSkillsURL.appendingPathComponent(skill.id)
        let sourceDir = repoDir.appendingPathComponent(skill.folderPath)

        // If already exists, delete first then copy (overwrite installation)
        if fm.fileExists(atPath: canonicalDir.path) {
            try fm.removeItem(at: canonicalDir)
        }

        // Ensure parent directory exists
        if !fm.fileExists(atPath: SkillScanner.sharedSkillsURL.path) {
            try fm.createDirectory(at: SkillScanner.sharedSkillsURL, withIntermediateDirectories: true)
        }

        // copyItem is like cp -r, recursively copies entire directory
        try fm.copyItem(at: sourceDir, to: canonicalDir)

        // 3. Create symlinks for selected Agents
        for agent in targetAgents {
            // Codex directly uses ~/.agents/skills/ directory, no symlink needed
            if agent == .codex { continue }
            // Use try? to ignore existing symlink errors (idempotent operation)
            try? SymlinkManager.createSymlink(from: canonicalDir, to: agent)
        }

        // 4. Update lock file
        // Ensure lock file exists (may not exist on first installation)
        try await lockFileManager.createIfNotExists()

        // ISO 8601 timestamp (consistent with npx skills CLI format)
        let now = ISO8601DateFormatter().string(from: Date())
        let entry = LockEntry(
            source: repoSource,
            sourceType: "github",
            sourceUrl: repoURL,
            skillPath: skill.skillMDPath,
            skillFolderHash: treeHash,
            installedAt: now,
            updatedAt: now
        )
        try await lockFileManager.updateEntry(skillName: skill.id, entry: entry)

        // 5. Refresh UI
        await refresh()
    }

    // MARK: - F12: Update Check

    /// Check for updates for a single skill
    ///
    /// Flow:
    /// 1. Get source repository URL and skillPath from lockEntry
    /// 2. Check if CommitHashCache has local commit hash
    ///    - Yes: use shallow clone (fast, only fetch remote latest state)
    ///    - No (old skill, installed via npx skills): use full clone, search git history for backfill
    /// 3. Get remote tree hash and commit hash
    /// 4. Compare with local lockEntry.skillFolderHash
    /// 5. Clean up temporary directory
    ///
    /// - Parameter skill: Skill to check (must have lockEntry)
    /// - Returns: Tuple (has update, remote tree hash, remote commit hash)
    func checkForUpdate(skill: Skill) async throws -> (hasUpdate: Bool, remoteHash: String?, remoteCommitHash: String?) {
        guard let lockEntry = skill.lockEntry else {
            return (false, nil, nil)
        }

        // Derive folderPath from skillPath (remove trailing "/SKILL.md")
        let folderPath: String
        if lockEntry.skillPath.hasSuffix("/SKILL.md") {
            folderPath = String(lockEntry.skillPath.dropLast("/SKILL.md".count))
        } else {
            folderPath = lockEntry.skillPath
        }

        // Check if CommitHashCache has local commit hash
        let localCommitHash = await commitHashCache.getHash(for: skill.id)
        // If no commit hash (old skill), need full clone to search git history for backfill
        let needsBackfill = localCommitHash == nil

        // Decide clone depth based on whether backfill is needed
        let repoDir = try await gitService.cloneRepo(repoURL: lockEntry.sourceUrl, shallow: !needsBackfill)
        defer {
            // defer ensures cleanup runs regardless of how function returns (similar to Go's defer or Java's finally)
            Task { await gitService.cleanupTempDirectory(repoDir) }
        }

        // Get remote tree hash
        let remoteHash = try await gitService.getTreeHash(for: folderPath, in: repoDir)

        // Get remote commit hash
        let remoteCommitHash = try await gitService.getCommitHash(in: repoDir)

        // Backfill: if local doesn't have commit hash, search git history for matching commit
        if needsBackfill {
            if let foundHash = try await gitService.findCommitForTreeHash(
                treeHash: lockEntry.skillFolderHash, folderPath: folderPath, in: repoDir
            ) {
                // Found matching commit hash, persist to cache (won't search next time)
                await commitHashCache.setHash(for: skill.id, hash: foundHash)
                try? await commitHashCache.save()
            }
        }

        // Compare hashes
        let hasUpdate = remoteHash != lockEntry.skillFolderHash
        return (hasUpdate, remoteHash, remoteCommitHash)
    }

    /// Batch check updates for all skills with lockEntry
    ///
    /// Optimization strategy: group by sourceUrl, clone each repository only once,
    /// then batch get tree hash and commit hash for each skill to compare.
    ///
    /// Smart clone depth: check if any skill in the group lacks commit hash (from cache),
    /// if so use full clone (need to search git history for backfill), otherwise use shallow clone (faster).
    func checkAllUpdates() async {
        isCheckingUpdates = true
        defer { isCheckingUpdates = false }

        // Collect all skills with lockEntry, group by sourceUrl
        // Dictionary(grouping:by:) is similar to Java Stream's Collectors.groupingBy()
        let skillsWithLock = skills.filter { $0.lockEntry != nil }

        // Set all skills to be checked to .checking state
        // So UI list immediately shows spinner, user knows which skills are being checked
        for skill in skillsWithLock {
            updateStatuses[skill.id] = .checking
        }

        let grouped = Dictionary(grouping: skillsWithLock) { $0.lockEntry!.sourceUrl }

        for (sourceUrl, groupSkills) in grouped {
            do {
                // Check if any skill in this group lacks commit hash
                // If so, need full clone to support backfill (search git history to restore commit hash)
                var needsFullClone = false
                for skill in groupSkills {
                    let cached = await commitHashCache.getHash(for: skill.id)
                    if cached == nil {
                        needsFullClone = true
                        break
                    }
                }

                // Clone each repository only once, decide clone depth based on whether backfill is needed
                let repoDir = try await gitService.cloneRepo(repoURL: sourceUrl, shallow: !needsFullClone)

                // Get remote latest commit hash (entire repository shares one HEAD commit)
                let remoteCommitHash = try await gitService.getCommitHash(in: repoDir)

                for skill in groupSkills {
                    guard let lockEntry = skill.lockEntry else { continue }

                    // Derive folderPath
                    let folderPath: String
                    if lockEntry.skillPath.hasSuffix("/SKILL.md") {
                        folderPath = String(lockEntry.skillPath.dropLast("/SKILL.md".count))
                    } else {
                        folderPath = lockEntry.skillPath
                    }

                    do {
                        let remoteHash = try await gitService.getTreeHash(for: folderPath, in: repoDir)
                        let hasUpdate = remoteHash != lockEntry.skillFolderHash

                        // Update status dictionary: use enum value instead of boolean
                        updateStatuses[skill.id] = hasUpdate ? .hasUpdate : .upToDate

                        // Backfill: for skills lacking commit hash, search from git history
                        let localCached = await commitHashCache.getHash(for: skill.id)
                        var currentLocalHash = localCached
                        if localCached == nil {
                            if let foundHash = try? await gitService.findCommitForTreeHash(
                                treeHash: lockEntry.skillFolderHash, folderPath: folderPath, in: repoDir
                            ) {
                                await commitHashCache.setHash(for: skill.id, hash: foundHash)
                                currentLocalHash = foundHash
                            }
                        }

                        // Sync to skills array (find corresponding skill and update)
                        if let index = skills.firstIndex(where: { $0.id == skill.id }) {
                            skills[index].hasUpdate = hasUpdate
                            skills[index].remoteTreeHash = hasUpdate ? remoteHash : nil
                            // Store remote commit hash for generating GitHub compare URL
                            skills[index].remoteCommitHash = hasUpdate ? remoteCommitHash : nil
                            // Update local commit hash (may have just been obtained via backfill)
                            skills[index].localCommitHash = currentLocalHash
                        }
                    } catch {
                        // Single skill check failed: mark as .error state, UI will show warning icon
                        updateStatuses[skill.id] = .error(error.localizedDescription)
                        continue
                    }
                }

                // Save cache once after backfill (reduce disk IO)
                try? await commitHashCache.save()

                // Clean up temporary directory
                await gitService.cleanupTempDirectory(repoDir)
            } catch {
                // Repository clone failed: mark all skills under this repo as .error
                for skill in groupSkills {
                    updateStatuses[skill.id] = .error(error.localizedDescription)
                }
                continue
            }
        }
    }

    /// Execute update: overwrite local with remote files, update lock entry
    ///
    /// - Parameters:
    ///   - skill: Skill to update
    ///   - remoteHash: Remote latest tree hash
    func updateSkill(_ skill: Skill, remoteHash: String) async throws {
        guard let lockEntry = skill.lockEntry else { return }

        // Derive folderPath
        let folderPath: String
        if lockEntry.skillPath.hasSuffix("/SKILL.md") {
            folderPath = String(lockEntry.skillPath.dropLast("/SKILL.md".count))
        } else {
            folderPath = lockEntry.skillPath
        }

        // 1. Clone source repository
        let repoDir = try await gitService.shallowClone(repoURL: lockEntry.sourceUrl)

        // 2. Get new commit hash and write to cache
        let newCommitHash = try await gitService.getCommitHash(in: repoDir)
        await commitHashCache.setHash(for: skill.id, hash: newCommitHash)
        try? await commitHashCache.save()

        // 3. Copy files to overwrite canonical directory
        let fm = FileManager.default
        let sourceDir = repoDir.appendingPathComponent(folderPath)
        let canonicalDir = skill.canonicalURL

        // Delete old files then copy new files
        if fm.fileExists(atPath: canonicalDir.path) {
            try fm.removeItem(at: canonicalDir)
        }
        try fm.copyItem(at: sourceDir, to: canonicalDir)

        // 4. Update lock entry (new hash + new updatedAt)
        let now = ISO8601DateFormatter().string(from: Date())
        var updatedEntry = lockEntry
        updatedEntry.skillFolderHash = remoteHash
        updatedEntry.updatedAt = now
        try await lockFileManager.updateEntry(skillName: skill.id, entry: updatedEntry)

        // 5. Clean up temporary directory
        await gitService.cleanupTempDirectory(repoDir)

        // 6. Clear update status (restore to unchecked state after update completes)
        updateStatuses[skill.id] = .notChecked

        // 7. Refresh UI
        await refresh()
    }

    // MARK: - Helper Methods

    /// Get local commit hash for specified skill (read from CommitHashCache)
    ///
    /// This method is exposed for ViewModel use because commitHashCache is private.
    /// Call after checkForUpdate to get the commit hash that may have been newly obtained via backfill.
    func getCachedCommitHash(for skillName: String) async -> String? {
        await commitHashCache.getHash(for: skillName)
    }

    /// Get a merged, deduplicated repo history list (lock file installed sources + scan history)
    ///
    /// Data sources:
    /// 1. `skills` array's `lockEntry.source`/`sourceUrl` (from lock file)
    /// 2. `commitHashCache.getRepoHistory()` (user's scan history)
    ///
    /// Dedup strategy: by `source` field (case-insensitive), lock file entries take priority
    /// since they have actual install records. Returns a tuple array for easy ViewModel consumption.
    ///
    /// - Returns: Deduplicated repo list, each with source (e.g. "owner/repo") and sourceUrl
    func getRepoHistory() async -> [(source: String, sourceUrl: String)] {
        // Use a Set to track seen sources (lowercased) for O(1) case-insensitive dedup.
        // GitHub URLs are case-insensitive, so "Owner/Repo" and "owner/repo" are the same repo.
        var seen = Set<String>()
        var result: [(source: String, sourceUrl: String)] = []

        // 1. Extract unique (source, sourceUrl) pairs from installed skills
        // Lock file entries are added first since installed repos are more valuable
        for skill in skills {
            guard let entry = skill.lockEntry else { continue }
            // Skip empty source (shouldn't happen in practice, but defensive programming)
            guard !entry.source.isEmpty else { continue }
            if seen.insert(entry.source.lowercased()).inserted {
                // insert returns (inserted: Bool, memberAfterInsert), similar to Go's map ok pattern
                result.append((source: entry.source, sourceUrl: entry.sourceUrl))
            }
        }

        // 2. Supplement with scan history (repos not already covered by lock file)
        let history = await commitHashCache.getRepoHistory()
        for entry in history {
            if seen.insert(entry.source.lowercased()).inserted {
                result.append((source: entry.source, sourceUrl: entry.sourceUrl))
            }
        }

        return result
    }

    /// Save a repo scan history entry to cache
    ///
    /// Called by SkillInstallViewModel after a successful scan,
    /// so the repo appears in the "Recent Repositories" list next time the Install Sheet opens.
    ///
    /// - Parameters:
    ///   - source: Repo source identifier (e.g. "crossoverJie/skills")
    ///   - sourceUrl: Full repo URL (e.g. "https://github.com/crossoverJie/skills.git")
    func saveRepoHistory(source: String, sourceUrl: String) async {
        await commitHashCache.addRepoHistory(source: source, sourceUrl: sourceUrl)
        try? await commitHashCache.save()
    }

    /// Filter skills by Agent
    func skills(for agentType: AgentType) -> [Skill] {
        skills.filter { skill in
            skill.installations.contains { $0.agentType == agentType }
        }
    }

    /// Search skills (by name, description, and author/source)
    /// Besides matching displayName and description, also supports:
    /// - lockEntry?.source: repository source from lock file (e.g. "crossoverJie/skills"), suitable for filtering by organization/author
    /// - metadata.author: author field from SKILL.md frontmatter (optional)
    func search(query: String) -> [Skill] {
        guard !query.isEmpty else { return skills }
        let lowered = query.lowercased()
        return skills.filter {
            $0.displayName.lowercased().contains(lowered) ||
            $0.metadata.description.lowercased().contains(lowered) ||
            ($0.lockEntry?.source.lowercased().contains(lowered) ?? false) ||
            ($0.metadata.author?.lowercased().contains(lowered) ?? false)
        }
    }

    // MARK: - Link to Repository (manual repository linking)

    /// Manually link a skill without lockEntry to a GitHub repository
    ///
    /// Flow:
    /// 1. normalizeRepoURL() validates and normalizes URL input
    /// 2. shallow clone remote repository
    /// 3. scanSkillsInRepo scans skills in repository, matches by skill.id
    /// 4. Get tree hash + commit hash
    /// 5. Sync remote files to local canonical directory (ensure local files match hash)
    /// 6. Write to commitHashCache (linkedSkills + skills two maps)
    /// 7. refresh() to refresh UI
    ///
    /// Link info is stored in SkillDeck private cache (~/.agents/.skilldeck-cache.json),
    /// does not modify skill-lock.json (to avoid affecting npx skills behavior).
    /// During refresh(), link info is read from cache and synthesized into LockEntry on Skill model,
    /// thus reusing existing update check flow.
    ///
    /// - Parameters:
    ///   - skill: Skill to link (must have no lockEntry)
    ///   - repoInput: User input repository address (supports "owner/repo" or full URL)
    func linkSkillToRepository(_ skill: Skill, repoInput: String) async throws {
        // 1. Validate and normalize URL
        let (repoURL, source) = try GitService.normalizeRepoURL(repoInput)

        // 2. shallow clone remote repository
        let repoDir: URL
        do {
            repoDir = try await gitService.shallowClone(repoURL: repoURL)
        } catch {
            throw LinkError.gitError(error.localizedDescription)
        }
        // defer ensures cleanup runs regardless of how function returns (similar to Go's defer)
        defer {
            Task { await gitService.cleanupTempDirectory(repoDir) }
        }

        // 3. Scan skills in repository, match by skill.id
        let discoveredSkills = await gitService.scanSkillsInRepo(repoDir: repoDir)
        guard let matched = discoveredSkills.first(where: { $0.id == skill.id }) else {
            throw LinkError.skillNotFoundInRepo(skill.id)
        }

        // 4. Get tree hash and commit hash
        let treeHash = try await gitService.getTreeHash(for: matched.folderPath, in: repoDir)
        let commitHash = try await gitService.getCommitHash(in: repoDir)

        // 5. Sync remote files to local canonical directory
        // Ensure local files match the stored skillFolderHash,
        // otherwise hash comparison baseline in subsequent checkForUpdate will be inaccurate
        let fm = FileManager.default
        let sourceDir = repoDir.appendingPathComponent(matched.folderPath)
        let canonicalDir = skill.canonicalURL

        // Delete old files then copy new files (consistent with installSkill/updateSkill)
        if fm.fileExists(atPath: canonicalDir.path) {
            try fm.removeItem(at: canonicalDir)
        }
        // Ensure parent directory exists
        let parentDir = canonicalDir.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        // copyItem recursively copies entire directory (similar to cp -r)
        try fm.copyItem(at: sourceDir, to: canonicalDir)

        // 6. Write to commitHashCache (two maps)
        // 6a. skills map: store commit hash (for subsequent compare URL)
        await commitHashCache.setHash(for: skill.id, hash: commitHash)

        // 6b. linkedSkills map: store complete link info (for synthesizing LockEntry during refresh)
        let now = ISO8601DateFormatter().string(from: Date())
        let linkedInfo = CommitHashCache.LinkedSkillInfo(
            source: source,
            sourceType: "github",
            sourceUrl: repoURL,
            skillPath: matched.skillMDPath,
            skillFolderHash: treeHash,
            linkedAt: now
        )
        await commitHashCache.setLinkedInfo(for: skill.id, info: linkedInfo)

        // Persist to disk
        try await commitHashCache.save()

        // 7. Refresh UI — refresh reads link info from cache and synthesizes LockEntry
        await refresh()
    }

    // MARK: - App Update (application self-update)

    /// Check if SkillDeck app itself has a new version
    ///
    /// Flow:
    /// 1. Read current version (from Info.plist or fallback to "dev")
    /// 2. "dev" version skips check (no .app bundle when launched via swift run in development)
    /// 3. Non-force mode respects 4-hour interval (avoid frequent GitHub API requests)
    /// 4. Call GitHub API to get latest Release
    /// 5. Compare versions using VersionComparator
    /// 6. If update available, set appUpdateInfo to trigger UI refresh
    ///
    /// - Parameter force: Whether to force check (ignore 4-hour interval, for manual trigger)
    func checkForAppUpdate(force: Bool = false) async {
        // Read current version
        // CFBundleShortVersionString is the version field in Info.plist
        // When launched via swift run, Bundle.main has no Info.plist, fallback to "dev"
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

        // "dev" version only skips automatic check (auto-trigger on app launch)
        // When user manually clicks "Check for Updates" (force=true), even dev version should execute check and show results
        // This allows testing update check flow in development environment
        if currentVersion == "dev" && !force { return }

        // Check 4-hour interval in non-force mode
        // force = true is for Settings page "Check for Updates" button (manual trigger, not limited by interval)
        if !force && !updateChecker.shouldAutoCheck() { return }

        isCheckingAppUpdate = true
        updateError = nil

        do {
            // Call GitHub API to get latest Release (throws version, errors no longer silently swallowed)
            let releaseInfo = try await updateChecker.fetchLatestRelease()

            // Record this check time (regardless of whether update exists, to avoid repeated requests in short time)
            updateChecker.recordCheckTime()

            // "dev" version is treated as always having updates (any Release counts as new version in development)
            // Release versions use VersionComparator for semantic comparison
            if currentVersion == "dev" || VersionComparator.isNewer(current: currentVersion, latest: releaseInfo.version) {
                appUpdateInfo = releaseInfo
            } else {
                // Current is already latest, clear previous update reminder (if any)
                appUpdateInfo = nil
            }
        } catch {
            // Silently ignore errors during automatic check (don't disturb user)
            // Show specific error message when user manually triggers (force=true) for troubleshooting
            if force {
                updateError = error.localizedDescription
            }
        }

        isCheckingAppUpdate = false
    }

    /// Execute app update: download zip → extract → replace .app → restart
    ///
    /// Call timing: User clicks "Update Now" button on Settings About page
    ///
    /// Flow:
    /// 1. Get download URL from appUpdateInfo
    /// 2. Download zip via UpdateChecker.downloadUpdate and report progress
    /// 3. Extract and replace via UpdateChecker.installUpdate
    /// 4. App will auto-restart (done by shell script)
    ///
    /// Error handling: Unlike detection phase, download/install errors will be shown to user
    func performUpdate() async {
        guard let updateInfo = appUpdateInfo else { return }

        isDownloadingUpdate = true
        downloadProgress = 0
        updateError = nil

        do {
            // Download zip file, update progress via closure callback
            // @MainActor is already marked on this class, so self.downloadProgress assignment executes on main thread
            // @Sendable closure needs Task { @MainActor in } to return to main thread to update UI state
            let zipPath = try await updateChecker.downloadUpdate(
                from: updateInfo.downloadURL
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }

            // Install update (extract → replace → restart)
            // Note: if installation succeeds, app will be terminated, subsequent code won't execute
            try await updateChecker.installUpdate(zipPath: zipPath)
        } catch {
            // Download or installation failed, show error message to user
            updateError = error.localizedDescription
            isDownloadingUpdate = false
        }
    }

    /// Dismiss app update reminder (user manually ignores)
    func dismissAppUpdate() {
        appUpdateInfo = nil
        updateError = nil
    }
}
