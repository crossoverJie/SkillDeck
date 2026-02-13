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

    /// Current installation flow phase
    var phase: Phase = .inputURL

    /// All skills discovered in the repository
    var discoveredSkills: [GitService.DiscoveredSkill] = []

    /// Set of skill names selected by user for installation
    /// Set provides O(1) lookup, similar to Java's HashSet
    var selectedSkillNames: Set<String> = []

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
            let discovered = await gitService.scanSkillsInRepo(repoDir: repoDir)

            guard !discovered.isEmpty else {
                phase = .error("No skills found in this repository.")
                return
            }

            discoveredSkills = discovered

            // 5. Mark already installed skills
            alreadyInstalledNames = Set(skillManager.skills.map(\.id))

            // Select all uninstalled skills by default
            selectedSkillNames = Set(discovered.map(\.id).filter { !alreadyInstalledNames.contains($0) })

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
        guard !selectedSkillNames.isEmpty else { return }
        guard let repoDir = tempRepoDir else {
            phase = .error("Repository data not available. Please scan again.")
            return
        }

        phase = .installing
        installedCount = 0
        let total = selectedSkillNames.count

        for skill in discoveredSkills where selectedSkillNames.contains(skill.id) {
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
                // Single skill installation failure doesn't block other skills
                // Error info is recorded (can be extended to show detailed error list in the future)
                continue
            }
        }

        phase = .completed
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

    /// Toggle selection state of a skill
    /// symmetricDifference is Set's symmetric difference operation: remove if exists, add if not
    /// Similar to Java Set's toggle operation
    func toggleSkillSelection(_ skillName: String) {
        if selectedSkillNames.contains(skillName) {
            selectedSkillNames.remove(skillName)
        } else {
            selectedSkillNames.insert(skillName)
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
        selectedSkillNames = []
        selectedAgents = [.claudeCode]
        alreadyInstalledNames = []
        progressMessage = ""
        installedCount = 0
    }
}
