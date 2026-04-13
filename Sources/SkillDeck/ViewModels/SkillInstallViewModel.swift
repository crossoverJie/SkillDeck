import Foundation

/// SkillInstallViewModel manages the state and logic for the F10 (one-click install) sheet
///
/// Installation flow consists of two steps:
/// 1. User inputs GitHub repository URL → shallow clone → scan for skills → display list
/// 2. User selects skills and Agents to install → execute installation → complete
///
/// @MainActor ensures all properties update on the main thread (UI-bound state must be on main thread)
/// @Observable enables SwiftUI to automatically track property changes and refresh views
@MainActor
@Observable
/// Identifiable protocol requires a unique id property so `.sheet(item:)` can use it to determine
/// when to show/hide the sheet (item != nil → show, nil → hide)
/// This is safer than `.sheet(isPresented:)` + extra @State, avoiding double-state synchronization timing issues
final class SkillInstallViewModel: Identifiable {

    /// Unique identifier, required property for Identifiable protocol
    /// Each new ViewModel instance automatically generates a new UUID
    let id = UUID()

    // MARK: - Phase Enum

    /// Installation flow phases (finite state machine)
    /// Similar to Java enum, but Swift enum can have associated values
    enum Phase: Equatable {
        /// Initial phase: waiting for user to input URL
        case inputURL
        /// Cloning repository and scanning skills
        case fetching
        /// Skills discovered, waiting for user selection
        case selectSkills
        /// Installing selected skills
        case installing
        /// Installation completed
        case completed
        /// Error occurred, with error message attached
        /// Associated values let enum cases carry data (Java enums lack this feature)
        case error(String)

        // Manual Equatable implementation: error case only compares type not message content
        // Default Equatable synthesis handles this automatically, but explicitly implemented here to ensure correct behavior
        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.inputURL, .inputURL),
                 (.fetching, .fetching),
                 (.selectSkills, .selectSkills),
                 (.installing, .installing),
                 (.completed, .completed):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: - State

    /// User input repository address (supports "owner/repo" or full URL)
    var repoURLInput = ""

    /// F09: Whether to auto-trigger fetch when the install sheet appears
    ///
    /// When opened from Registry Browser with a pre-filled repo URL, this flag
    /// tells the view to automatically start cloning and scanning on appear,
    /// so the user doesn't need to manually click "Scan".
    /// Reset to false after the auto-fetch triggers (one-shot flag).
    var autoFetch = false

    /// F09: Target skill ID to pre-select after scanning
    ///
    /// When installing from Registry Browser, this is set to the specific skill's skillId
    /// (e.g., "vercel-react-best-practices"). After scanning the repo, only this skill
    /// will be pre-selected instead of all skills.
    /// When nil (manual install flow), all uninstalled skills are selected by default.
    var targetSkillId: String?

    /// Current installation flow phase
    var phase: Phase = .inputURL

    /// All skills discovered in the repository
    var discoveredSkills: [GitService.DiscoveredSkill] = []

    /// Set of skill folder paths selected by user for installation
    /// Using folderPath (not id) as the key because multiple skills can have the same id
    /// (e.g., "skills/pua" and "codex/pua" both have id="pua" but different folderPaths)
    /// Set provides O(1) lookup, similar to Java's HashSet
    var selectedSkillPaths: Set<String> = []

    /// Set of target Agents selected by user (Claude Code selected by default)
    var selectedAgents: Set<AgentType> = [.claudeCode]

    /// Set of already installed skill names (used to mark "already installed" in the list)
    var alreadyInstalledNames: Set<String> = []

    /// Progress message
    var progressMessage = ""

    /// Number of skills successfully installed
    var installedCount = 0

    /// Merged and deduplicated repo history (from lock file + scan history)
    /// Loaded asynchronously via loadHistory() after ViewModel creation
    var repoHistory: [(source: String, sourceUrl: String)] = []

    // MARK: - Dependencies

    /// SkillManager reference, used to execute installation and check installed status
    private let skillManager: SkillManager

    /// Git operation service
    private let gitService = GitService()

    /// Cloned temporary directory URL (persisted between fetch and install, cleaned up when sheet closes)
    private var tempRepoDir: URL?

    /// Normalized repository URL and source identifier
    private var normalizedRepoURL: String = ""
    private var normalizedSource: String = ""

    // MARK: - Init

    init(skillManager: SkillManager) {
        self.skillManager = skillManager
    }

    // MARK: - Actions

    /// Load repo history (merged from lock file + scan history)
    ///
    /// Called from the View's .task modifier (not in init, because init is synchronous
    /// while getRepoHistory is async and requires await).
    /// .task runs async code when the view first appears, similar to Android's onResume + coroutine
    func loadHistory() async {
        repoHistory = await skillManager.getRepoHistory()
    }

    /// Select a history entry: auto-fill URL input and trigger Scan
    ///
    /// Called when the user taps a row in the Install Sheet's history list.
    /// Uses the source (owner/repo) format as input — fetchRepository() will normalize it internally.
    ///
    /// - Parameter source: Repo source identifier (e.g. "crossoverJie/skills")
    /// - Parameter sourceUrl: Full repo URL (e.g. "https://github.com/crossoverJie/skills.git")
    func selectHistoryRepo(source: String, sourceUrl: String) async {
        // Use source format (owner/repo) as input; fetchRepository normalizes it internally
        repoURLInput = source
        await fetchRepository()
    }

    /// Step 1: Clone repository and scan for skills
    ///
    /// Execution flow:
    /// 1. Normalize URL (supports "owner/repo" and full URL formats)
    /// 2. Check if git is available
    /// 3. Shallow clone repository
    /// 4. Scan SKILL.md files
    /// 5. Mark already installed skills
    /// 6. Transition to selection phase
    func fetchRepository() async {
        phase = .fetching
        progressMessage = "Validating URL..."

        do {
            // 1. Normalize URL
            let (repoURL, source) = try GitService.normalizeRepoURL(repoURLInput)
            normalizedRepoURL = repoURL
            normalizedSource = source

            // 2. Check git
            progressMessage = "Checking git..."
            let gitAvailable = await gitService.checkGitAvailable()
            guard gitAvailable else {
                phase = .error("Git is not installed. Please install git first.")
                return
            }

            // 3. Shallow clone
            progressMessage = "Cloning repository..."
            let repoDir = try await gitService.shallowClone(repoURL: repoURL)
            tempRepoDir = repoDir

            // 4. Scan skills
            progressMessage = "Scanning skills..."
            let discovered = await gitService.scanSkillsInRepo(repoDir: repoDir, repoURL: normalizedRepoURL)

            guard !discovered.isEmpty else {
                phase = .error("No skills found in this repository.")
                return
            }

            // Deduplicate display names: if multiple skills have the same metadata.name,
            // append the folder path to make them distinguishable in the UI.
            discoveredSkills = deduplicateSkillNames(discovered)

            // 5. Mark already installed skills
            alreadyInstalledNames = Set(skillManager.skills.map(\.id))

            // Pre-select skills based on context:
            // - F09 Registry install (targetSkillId is set): only select the specific target skill
            // - Manual install (targetSkillId is nil): select all uninstalled skills
            if let targetId = targetSkillId {
                // From Registry Browser: only select the specific skill the user clicked
                // Filter to ensure the target skill exists in the repo and isn't already installed
                // Use folderPath as the selection key to handle duplicate skill IDs
                selectedSkillPaths = Set(
                    discovered.filter { $0.id == targetId && !alreadyInstalledNames.contains($0.id) }
                        .map(\.folderPath)
                )
            } else {
                // Manual install: select all uninstalled skills by default
                // Use folderPath as the selection key
                selectedSkillPaths = Set(discovered.filter { !alreadyInstalledNames.contains($0.id) }
                    .map(\.folderPath))
            }

            // Save scan history (so this repo appears in "Recent Repositories" next time)
            await skillManager.saveRepoHistory(source: normalizedSource, sourceUrl: normalizedRepoURL)

            // 6. Transition to selection phase
            phase = .selectSkills
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    /// Step 2: Install selected skills
    ///
    /// Install selected skills one by one, updating progress message
    func installSelected() async {
        guard !selectedSkillPaths.isEmpty else { return }
        guard let repoDir = tempRepoDir else {
            phase = .error("Repository data not available. Please scan again.")
            return
        }

        phase = .installing
        installedCount = 0
        var failedSkills: [(name: String, error: String)] = []
        let total = selectedSkillPaths.count

        // Match skills by folderPath (unique) but install using skill.id (directory name)
        for skill in discoveredSkills where selectedSkillPaths.contains(skill.folderPath) {
            progressMessage = "Installing \(skill.id) (\(installedCount + 1)/\(total))..."

            do {
                try await skillManager.installSkill(
                    from: repoDir,
                    skill: skill,
                    repoSource: normalizedSource,
                    repoURL: normalizedRepoURL,
                    targetAgents: selectedAgents
                )
                installedCount += 1
            } catch {
                // Record failed skill with error message for display
                failedSkills.append((name: skill.id, error: error.localizedDescription))
                continue
            }
        }

        // Show error if some skills failed to install
        if !failedSkills.isEmpty && installedCount == 0 {
            let errorMessages = failedSkills.map { "\($0.name): \($0.error)" }.joined(separator: "\n")
            phase = .error("Failed to install skills:\n\(errorMessages)")
        } else {
            phase = .completed
        }
    }

    /// Clean up temporary directory (called when sheet closes)
    ///
    /// Use Task to wrap actor method calls because cleanup is synchronous but needs to await actor methods
    func cleanup() {
        if let tempRepoDir {
            let dir = tempRepoDir
            self.tempRepoDir = nil
            Task {
                await gitService.cleanupTempDirectory(dir)
            }
        }
    }

    /// Toggle selection state of a skill by its folder path
    /// symmetricDifference is Set's symmetric difference operation: remove if exists, add if not
    /// Similar to Java Set's toggle operation
    /// - Parameter folderPath: The unique folder path of the skill (e.g., "skills/pua")
    func toggleSkillSelection(_ folderPath: String) {
        if selectedSkillPaths.contains(folderPath) {
            selectedSkillPaths.remove(folderPath)
        } else {
            selectedSkillPaths.insert(folderPath)
        }
    }

    /// Toggle selection state of an Agent
    func toggleAgentSelection(_ agent: AgentType) {
        if selectedAgents.contains(agent) {
            selectedAgents.remove(agent)
        } else {
            selectedAgents.insert(agent)
        }
    }

    /// Reset to initial state (start over)
    func reset() {
        cleanup()
        phase = .inputURL
        repoURLInput = ""
        discoveredSkills = []
        selectedSkillPaths = []
        selectedAgents = [.claudeCode]
        alreadyInstalledNames = []
        progressMessage = ""
        installedCount = 0
    }

    // MARK: - Private Methods

    /// Deduplicate skill display names by appending folder path when conflicts exist.
    ///
    /// Problem: Some repositories (e.g., tanweai/pua) contain multiple skill directories
    /// with the same `name` field in their SKILL.md frontmatter (e.g., "pua").
    /// Without deduplication, the UI shows multiple entries with identical names,
    /// making it impossible for users to distinguish between them.
    ///
    /// Solution: Count occurrences of each display name. For names that appear multiple times,
    /// append the parent folder path to differentiate them (e.g., "pua (codex/pua)").
    ///
    /// - Parameter skills: Array of discovered skills from the repository scan
    /// - Returns: Array of skills with modified metadata names to ensure uniqueness
    private func deduplicateSkillNames(_ skills: [GitService.DiscoveredSkill]) -> [GitService.DiscoveredSkill] {
        // Count occurrences of each display name (using metadata.name, falling back to id)
        var nameCounts: [String: Int] = [:]
        for skill in skills {
            let displayName = skill.metadata.name.isEmpty ? skill.id : skill.metadata.name
            nameCounts[displayName, default: 0] += 1
        }

        // Build the result with deduplicated names
        return skills.map { skill in
            let displayName = skill.metadata.name.isEmpty ? skill.id : skill.metadata.name

            // If this name appears multiple times, append folder path to differentiate
            if nameCounts[displayName, default: 0] > 1 {
                // Create a modified metadata with disambiguated name
                let disambiguatedName = "\(displayName) (\(skill.folderPath))"
                let modifiedMetadata = SkillMetadata(
                    name: disambiguatedName,
                    description: skill.metadata.description,
                    license: skill.metadata.license,
                    metadata: skill.metadata.metadata,
                    allowedTools: skill.metadata.allowedTools
                )
                return GitService.DiscoveredSkill(
                    id: skill.id,
                    folderPath: skill.folderPath,
                    skillMDPath: skill.skillMDPath,
                    metadata: modifiedMetadata,
                    markdownBody: skill.markdownBody
                )
            } else {
                // No conflict, keep original
                return skill
            }
        }
    }
}
