import Foundation

/// RepositoryBrowserViewModel manages the state for browsing a single custom repository.
///
/// Each configured repository gets its own instance of this ViewModel, stored in
/// ContentView's `repoVMs: [UUID: RepositoryBrowserViewModel]` dictionary.
///
/// Responsibilities:
/// - Load the list of Skills available in the cloned repository (via RepositoryManager.scanSkills)
/// - Track search text for local filtering (no network request needed — all data is local)
/// - Trigger installation of a selected skill from already-synced local repository data
/// - Expose sync status so the UI can show a spinner while a git pull is in progress
///
/// @MainActor @Observable follows the same pattern as RegistryBrowserViewModel.
@MainActor
@Observable
final class RepositoryBrowserViewModel {

    // MARK: - State

    /// The repository this ViewModel represents.
    /// Must stay mutable so lastSyncedAt/name updates propagate to UI.
    var repository: SkillRepository

    /// All skills discovered in the cloned repository (unfiltered)
    var allSkills: [GitService.DiscoveredSkill] = []

    /// Skills shown in the list after applying searchText filter
    var displayedSkills: [GitService.DiscoveredSkill] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return allSkills }
        // Case-insensitive substring match on skill name or description
        return allSkills.filter { skill in
            skill.metadata.name.localizedCaseInsensitiveContains(text)
                || skill.metadata.description.localizedCaseInsensitiveContains(text)
        }
    }

    /// Search text for filtering the skill list (no debounce needed — filtering is synchronous)
    var searchText = ""

    /// Whether the initial skill scan is running (shows ProgressView in the list)
    var isLoading = false

    /// Error message (nil = no error)
    var errorMessage: String?

    /// Currently selected skill (drives the detail pane in ContentView)
    var selectedSkillID: String?

    /// Selected skill object resolved from `selectedSkillID`.
    ///
    /// This is consumed by ContentView's detail column for custom repositories.
    var selectedSkill: GitService.DiscoveredSkill? {
        guard let id = selectedSkillID else { return nil }
        return allSkills.first { $0.id == id }
    }

    /// Install sheet ViewModel — non-nil triggers the install sheet.
    /// Same pattern as RegistryBrowserViewModel.installVM.
    var installVM: SkillInstallViewModel?

    /// Current sync status for this repository.
    var syncStatus: SkillRepository.SyncStatus {
        skillManager.repoSyncStatuses[repository.id] ?? .idle
    }

    /// Whether this repository is currently syncing.
    var isSyncing: Bool {
        if case .syncing = syncStatus { return true }
        return false
    }

    /// Whether local installation is allowed now.
    /// Requires: cloned + at least one successful sync + not currently syncing.
    var canInstallFromLocal: Bool {
        repository.isCloned && repository.lastSyncedAt != nil && !isSyncing
    }

    /// Human-readable reason when install is disabled.
    var installDisabledReason: String? {
        if isSyncing { return "Repository is syncing. Please wait." }
        if !repository.isCloned || repository.lastSyncedAt == nil {
            return "Repository must be synced before installing."
        }
        return nil
    }

    // MARK: - Private

    private let skillManager: SkillManager

    // MARK: - Init

    init(repository: SkillRepository, skillManager: SkillManager) {
        self.repository = repository
        self.skillManager = skillManager
    }

    // MARK: - Public API

    /// Called when the RepositoryBrowserView first appears.
    ///
    /// Scans the local clone for SKILL.md files. This is a purely local operation —
    /// no network requests are made. The actual git pull (sync) is triggered separately
    /// by the user or on app startup.
    func onAppear() async {
        await loadSkills()
    }

    /// Refresh repository metadata from SkillManager (name, lastSyncedAt, enabled state, etc.).
    /// ContentView calls this whenever skillManager.repositories changes.
    func updateRepository(_ repository: SkillRepository) {
        self.repository = repository
    }

    /// Reload the skill list from the local clone directory.
    ///
    /// Called after a sync completes (to pick up any newly pulled skills)
    /// and on initial appear.
    ///
    /// Uses `RepositoryManager.scanSkills(in:)` which calls `GitService.scanSkillsInRepo`
    /// on the actor — this keeps file I/O off the main thread.
    ///
    /// - Parameter overrideError: If provided, this message is shown instead of the
    ///   generic "not yet synced" message. Used by `sync()` to surface actual git errors.
    func loadSkills(overrideError: String? = nil) async {
        isLoading = true
        // Only clear errorMessage here if we have no override; the override is shown after this call.
        if overrideError == nil { errorMessage = nil }

        // Delegate to RepositoryManager which handles actor isolation correctly.
        // The `await` suspends this @MainActor task while RepositoryManager does file I/O,
        // which helps avoid the NSTableView reentrant-delegate warning by not updating the
        // List's data source inside the same synchronous render pass.
        let skills = await skillManager.repositoryManager.scanSkills(in: repository)

        // Defer List data update to next run loop to avoid NSTableView reentrancy warning.
        // SwiftUI can trigger this warning when we update a List's data source while the
        // List is still in its layout/render pass (e.g., triggered by a button tap).
        await Task.yield()

        allSkills = skills
        // If selected skill no longer exists after reload/sync, clear stale selection.
        if let selectedSkillID, !allSkills.contains(where: { $0.id == selectedSkillID }) {
            self.selectedSkillID = nil
        }
        isLoading = false

        if let override = overrideError {
            // Show the actual git error (e.g., SSH auth failure, network error)
            errorMessage = override
        } else if !repository.isCloned && allSkills.isEmpty {
            errorMessage = "Repository not yet synced. Use the Sync button to clone it."
        }
    }

    /// Trigger installation of a discovered skill from the already-synced local repository.
    ///
    /// - Parameter skill: The discovered skill to install
    func installSkill(_ skill: GitService.DiscoveredSkill) {
        if let reason = installDisabledReason {
            errorMessage = reason
            return
        }
        guard !allSkills.isEmpty else {
            errorMessage = "No skills available to install. Please sync and try again."
            return
        }

        let vm = SkillInstallViewModel(skillManager: skillManager)
        vm.prepareForLocalRepository(
            repoDir: URL(fileURLWithPath: repository.localPath),
            repoURL: repository.repoURL,
            repoSource: sourceIdentifier(),
            discoveredSkills: allSkills,
            targetSkillId: skill.id
        )
        installVM = vm
    }

    /// Check if a discovered skill is already installed locally.
    ///
    /// Matches by skill ID (directory name). The skill is considered installed
    /// if SkillManager already has a Skill with the same ID in its scanned list.
    func isInstalled(_ skill: GitService.DiscoveredSkill) -> Bool {
        skillManager.skills.contains { $0.id == skill.id }
    }

    /// Sync this repository (git pull or clone) and reload the skill list.
    ///
    /// Delegates to SkillManager.syncRepository which updates repoSyncStatuses
    /// (observed by SidebarView for the spinner indicator).
    ///
    /// After sync, checks whether it succeeded or failed:
    /// - Success → calls loadSkills() to show newly discovered skills
    /// - Failure → passes the git error message to loadSkills() so it's visible to the user
    ///             (e.g., "SSH permission denied", "Host unreachable")
    func sync() async {
        errorMessage = nil  // Clear stale error before starting
        isLoading = true    // Show loading indicator while git clone/pull runs
        await skillManager.syncRepository(id: repository.id)

        // Surface the sync result to the user
        let status = skillManager.repoSyncStatuses[repository.id]
        if case .error(let gitError) = status {
            // Sync failed — show the actual git error (SSH auth issues, network problems, etc.)
            // Pass it as overrideError so loadSkills() doesn't replace it with the generic message.
            await loadSkills(overrideError: "Sync failed: \(gitError)")
        } else {
            // Success (or unexpected nil status) — reload skills normally
            await loadSkills()
        }
    }

    private func sourceIdentifier() -> String {
        let trimmed = repository.repoURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.lowercased().hasPrefix("git@"),
           let colonIdx = trimmed.firstIndex(of: ":") {
            var source = String(trimmed[trimmed.index(after: colonIdx)...])
            if source.hasSuffix(".git") {
                source = String(source.dropLast(4))
            }
            return source
        }

        if let components = URLComponents(string: trimmed) {
            var path = components.path
            while path.hasPrefix("/") { path.removeFirst() }
            while path.hasSuffix("/") { path.removeLast() }
            if path.hasSuffix(".git") {
                path = String(path.dropLast(4))
            }
            if !path.isEmpty { return path }
        }

        return repository.localSlug
    }
}
