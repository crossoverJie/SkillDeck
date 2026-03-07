import Foundation
import AppKit

/// LocalImportViewModel manages the state and logic for importing skills from local directories
///
/// Import flow consists of phases (finite state machine):
/// 1. selectPath — User picks a local directory via NSOpenPanel
/// 2. validating — Verify directory contains a valid SKILL.md
/// 3. selectAgents — User selects target Agents to install the skill to
/// 4. importing — Copy files and create symlinks
/// 5. completed — Import finished successfully
/// 6. error — Something went wrong, show error message
///
/// @MainActor ensures all properties update on the main thread (UI-bound state must be on main thread)
/// @Observable enables SwiftUI to automatically track property changes and refresh views
@MainActor
@Observable
/// Identifiable protocol requires a unique id property so `.sheet(item:)` can use it to determine
/// when to show/hide the sheet (item != nil → show, nil → hide)
final class LocalImportViewModel: Identifiable {

    /// Unique identifier, required property for Identifiable protocol
    let id = UUID()

    // MARK: - Phase Enum

    /// Import flow phases (finite state machine)
    /// Similar to Java enum, but Swift enum can have associated values (like Rust's enum variants)
    enum Phase: Equatable {
        /// Initial phase: waiting for user to select a local directory
        case selectPath
        /// Validating the selected directory (checking for SKILL.md, parsing)
        case validating
        /// Directory validated, waiting for user to select target Agents
        case selectAgents
        /// Importing skill (copying files, creating symlinks)
        case importing
        /// Import completed successfully
        case completed
        /// Error occurred, with error message attached
        case error(String)

        // Manual Equatable: error case compares message content
        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.selectPath, .selectPath),
                 (.validating, .validating),
                 (.selectAgents, .selectAgents),
                 (.importing, .importing),
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

    /// Current import flow phase
    var phase: Phase = .selectPath

    /// URL of the directory selected by the user (nil until a folder is picked)
    var selectedDirectoryURL: URL?

    /// Parsed metadata from the SKILL.md in the selected directory
    /// Populated during validation phase, used for preview display
    var skillMetadata: SkillMetadata?

    /// Skill name derived from the directory name (used as the canonical skill identifier)
    var skillName: String = ""

    /// Whether a skill with the same name already exists in the canonical directory
    /// When true, the UI shows a warning that the existing skill will be overwritten
    var alreadyExists: Bool = false

    /// Set of target Agents selected by user (Claude Code selected by default)
    var selectedAgents: Set<AgentType> = [.claudeCode]

    /// Progress message displayed during validating/importing phases
    var progressMessage = ""

    // MARK: - Dependencies

    /// SkillManager reference, used to execute the import and check existing skills
    private let skillManager: SkillManager

    // MARK: - Init

    init(skillManager: SkillManager) {
        self.skillManager = skillManager
    }

    // MARK: - Actions

    /// Show macOS native folder picker (NSOpenPanel) for user to select a skill directory
    ///
    /// NSOpenPanel is AppKit's file/folder selection dialog (similar to JFileChooser in Java Swing).
    /// Configured to allow selecting both files and directories:
    /// - If user selects a directory, use it directly
    /// - If user selects a SKILL.md file, resolve to its parent directory
    ///
    /// After selection, automatically triggers validation
    func openFolderPicker() {
        // NSOpenPanel must be created and run on the main thread (AppKit requirement)
        let panel = NSOpenPanel()
        // Allow selecting directories (the primary use case)
        panel.canChooseDirectories = true
        // Also allow selecting files (so user can pick SKILL.md directly)
        panel.canChooseFiles = true
        // Only allow single selection
        panel.allowsMultipleSelection = false
        // Dialog title and button text
        panel.title = "Select Skill Directory"
        panel.prompt = "Select"
        // Hint message shown at the top of the dialog
        panel.message = "Choose a directory containing SKILL.md, or select a SKILL.md file directly"
        // Show hidden files/directories (those starting with '.') so users can navigate into
        // paths like ~/.claude/skills/ or ~/.agents/skills/ which are common skill locations
        panel.showsHiddenFiles = true

        // runModal() shows the dialog and blocks until user confirms or cancels
        // Returns .OK if user clicked "Select", .cancel if user clicked "Cancel"
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        // If user selected a SKILL.md file, resolve to its parent directory
        // lastPathComponent returns the filename portion of the URL path
        if url.lastPathComponent == "SKILL.md" {
            selectedDirectoryURL = url.deletingLastPathComponent()
        } else {
            selectedDirectoryURL = url
        }

        // Auto-trigger validation after selection
        Task { await validateDirectory() }
    }

    /// Validate the selected directory contains a parseable SKILL.md
    ///
    /// Checks:
    /// 1. Directory exists on disk
    /// 2. Contains a SKILL.md file
    /// 3. SKILL.md is parseable (valid YAML frontmatter)
    ///
    /// On success, populates skillMetadata, skillName, and alreadyExists,
    /// then transitions to .selectAgents phase
    func validateDirectory() async {
        guard let dirURL = selectedDirectoryURL else {
            phase = .error("No directory selected")
            return
        }

        phase = .validating
        progressMessage = "Validating directory..."

        let fm = FileManager.default

        // 1. Check directory exists
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else {
            phase = .error("Selected path is not a valid directory: \(dirURL.path)")
            return
        }

        // 2. Check SKILL.md exists
        let skillMDURL = dirURL.appendingPathComponent("SKILL.md")
        guard fm.fileExists(atPath: skillMDURL.path) else {
            phase = .error("No SKILL.md found in the selected directory")
            return
        }

        // 3. Parse SKILL.md
        do {
            let result = try SkillMDParser.parse(fileURL: skillMDURL)
            skillMetadata = result.metadata
        } catch {
            phase = .error("Failed to parse SKILL.md: \(error.localizedDescription)")
            return
        }

        // Derive skill name from directory name (e.g., "agent-notifier")
        // lastPathComponent extracts the final path segment, equivalent to Go's filepath.Base()
        skillName = dirURL.lastPathComponent

        // Check if a skill with the same name already exists
        alreadyExists = skillManager.skills.contains { $0.id == skillName }

        // Validation passed, transition to agent selection phase
        phase = .selectAgents
    }

    /// Execute the import: copy files, create symlinks, update lock file
    ///
    /// Delegates to SkillManager.importLocalSkill() which handles all the heavy lifting.
    /// Transitions to .completed on success, .error on failure.
    func importSkill() async {
        guard let dirURL = selectedDirectoryURL else {
            phase = .error("No directory selected")
            return
        }

        phase = .importing
        progressMessage = "Importing \(skillName)..."

        do {
            try await skillManager.importLocalSkill(
                from: dirURL,
                skillName: skillName,
                targetAgents: selectedAgents
            )
            phase = .completed
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    /// Toggle selection state of an Agent
    /// If the Agent is already selected, remove it; otherwise, add it
    func toggleAgentSelection(_ agent: AgentType) {
        if selectedAgents.contains(agent) {
            selectedAgents.remove(agent)
        } else {
            selectedAgents.insert(agent)
        }
    }

    /// Reset to initial state (start over for importing another skill)
    func reset() {
        phase = .selectPath
        selectedDirectoryURL = nil
        skillMetadata = nil
        skillName = ""
        alreadyExists = false
        selectedAgents = [.claudeCode]
        progressMessage = ""
    }
}
