import Foundation

/// A dashboard row may originate from the configured global store or a specific project store.
/// `Skill.id` alone is not sufficient here because different projects can legitimately use the
/// same directory name, so identity is based on the canonical filesystem path.
struct DashboardSkillItem: Identifiable {
    enum Origin {
        case global
        case project(ProjectDashboardSkill)
    }

    let skill: Skill
    let origin: Origin

    var id: String { skill.canonicalURL.standardizedFileURL.path }
}

/// DashboardViewModel manages the state and interaction logic for the Dashboard page
///
/// In the MVVM architecture, the ViewModel acts as a bridge between View and Model:
/// - View observes ViewModel state changes through data binding
/// - View user actions invoke ViewModel methods
/// - ViewModel calls Service layer to handle business logic
///
/// @Observable enables SwiftUI to automatically track property changes and refresh the UI
/// @MainActor ensures all state modifications happen on the main thread (UI-safe)
@MainActor
@Observable
final class DashboardViewModel {

    /// Search keyword
    var searchText = ""

    /// Currently selected Agent filter (nil means show all)
    var selectedAgentFilter: AgentType?

    /// Sort order
    var sortOrder: SortOrder = .name

    /// Sort direction (ascending/descending)
    var sortDirection: SortDirection = .ascending

    /// Currently selected skill (used for navigation to detail page)
    var selectedSkillID: String?

    /// Whether to show disable confirmation dialog
    var showDisableConfirmation = false

    /// Dashboard row pending disablement. Its origin determines which storage scope is modified.
    var itemToDisable: DashboardSkillItem?

    /// Project skills are loaded independently because their lock file is scoped to each project.
    var projectItems: [DashboardSkillItem] = []

    /// Reversible archive records shown from the dashboard toolbar.
    var disabledSkills: [DisabledSkillRecord] = []
    var showsDisabledSkills = false

    /// Sort direction enum
    /// Swift enums can conform to multiple protocols:
    /// - CaseIterable: provides allCases collection for iterating over enum values
    enum SortDirection: CaseIterable {
        case ascending
        case descending

        /// Toggle sort direction, returning the opposite direction
        var toggled: SortDirection {
            self == .ascending ? .descending : .ascending
        }

        /// SF Symbols icon name: ascending uses up arrow, descending uses down arrow
        var iconName: String {
            self == .ascending ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"
        }

        /// Display text
        var displayName: String {
            self == .ascending ? "Ascending" : "Descending"
        }
    }

    /// Sort order enum
    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case scope = "Scope"
        case agent = "Agent Count"

        /// Each sort order corresponds to an SF Symbol icon
        var iconName: String {
            switch self {
            case .name: return "textformat.abc"
            case .scope: return "scope"
            case .agent: return "cpu"
            }
        }
    }

    /// Reference to global SkillManager (dependency injection)
    let skillManager: SkillManager
    let projectManager: ProjectManager

    init(skillManager: SkillManager, projectManager: ProjectManager) {
        self.skillManager = skillManager
        self.projectManager = projectManager
    }

    /// Exposes the project's revision as a SwiftUI task dependency without duplicating state.
    var projectRevision: Int { projectManager.dashboardRevision }

    /// Reads project source skills after ProjectManager has removed per-agent duplicates.
    func reloadProjectSkills() async {
        var items: [DashboardSkillItem] = []
        for projectSkill in projectManager.dashboardSkills {
            let service = ProjectSkillUpdateService(sourceRoot: projectSkill.row.sourceURL.deletingLastPathComponent())
            guard let skill = try? await service.loadSkill(named: projectSkill.row.name, at: projectSkill.row.sourceURL) else {
                continue
            }
            items.append(DashboardSkillItem(skill: skill, origin: .project(projectSkill)))
        }
        projectItems = items
    }

    /// Reloads the shared archive index; the archive is outside project directories by design.
    func reloadDisabledSkills() {
        do {
            disabledSkills = try DisabledSkillStore().records()
        } catch {
            skillManager.errorMessage = "读取已禁用技能失败：\(error.localizedDescription)"
        }
    }

    /// Restores the archived directory to its original global or project source and refreshes both lists.
    func restoreDisabledSkill(_ record: DisabledSkillRecord) async {
        do {
            try DisabledSkillStore().restore(record)
            await skillManager.refresh()
            projectManager.reload()
            await reloadProjectSkills()
            reloadDisabledSkills()
        } catch {
            skillManager.errorMessage = error.localizedDescription
        }
    }

    /// Calculates the list of skills to display based on current search, filter, and sort conditions
    /// Computed property: dynamically calculated on each access, similar to Java getter
    var filteredItems: [DashboardSkillItem] {
        var result = skillManager.skills.map { DashboardSkillItem(skill: $0, origin: .global) } + projectItems

        // 1. Search filtering
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { item in
                item.skill.displayName.lowercased().contains(query)
                    || item.skill.metadata.description.lowercased().contains(query)
                    || item.skill.id.lowercased().contains(query)
            }
        }

        // 2. Agent filtering
        if let agent = selectedAgentFilter {
            result = result.filter { item in
                guard case .global = item.origin else { return false }
                return item.skill.installations.contains { $0.agentType == agent }
            }
        }

        // 3. Sorting (ascending or descending based on sort direction)
        // In Swift closures, $0 and $1 are anonymous parameters, similar to Kotlin's it
        let ascending = sortDirection == .ascending
        switch sortOrder {
        case .name:
            result.sort {
                ascending
                    ? $0.skill.displayName.lowercased() < $1.skill.displayName.lowercased()
                    : $0.skill.displayName.lowercased() > $1.skill.displayName.lowercased()
            }
        case .scope:
            result.sort {
                ascending
                    ? $0.skill.scope.displayName < $1.skill.scope.displayName
                    : $0.skill.scope.displayName > $1.skill.scope.displayName
            }
        case .agent:
            // Agent Count defaults to descending (most first) for better visibility
            result.sort {
                ascending
                    ? $0.skill.installations.count < $1.skill.installations.count
                    : $0.skill.installations.count > $1.skill.installations.count
            }
        }

        return result
    }

    /// Finds the selected row by its path-based ID, avoiding collisions between same-named skills.
    func item(id: String) -> DashboardSkillItem? {
        filteredItems.first { $0.id == id } ?? (skillManager.skills.map { DashboardSkillItem(skill: $0, origin: .global) } + projectItems).first { $0.id == id }
    }

    /// Requests reversible skill disablement (shows confirmation dialog first).
    func requestDisable(item: DashboardSkillItem) {
        itemToDisable = item
        showDisableConfirmation = true
    }

    /// Confirms disablement
    func confirmDelete() async {
        guard let item = itemToDisable else { return }
        do {
            switch item.origin {
            case .global:
                try await skillManager.disableSkill(item.skill)
            case .project(let projectSkill):
                let service = ProjectSkillUpdateService(sourceRoot: projectSkill.row.sourceURL.deletingLastPathComponent())
                try await service.disableSkill(item.skill, projectName: projectSkill.project.name)
                projectManager.reload()
                await reloadProjectSkills()
            }
            reloadDisabledSkills()
        } catch {
            skillManager.errorMessage = "禁用技能失败：\(error.localizedDescription)"
        }
        itemToDisable = nil
        showDisableConfirmation = false
    }

    /// Cancels disablement
    func cancelDelete() {
        itemToDisable = nil
        showDisableConfirmation = false
    }
}
