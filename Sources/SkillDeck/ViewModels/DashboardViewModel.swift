import Foundation

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

    /// Whether to show delete confirmation dialog
    var showDeleteConfirmation = false

    /// Skill pending deletion
    var skillToDelete: Skill?

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
        case usage = "Usage Count"

        /// Each sort order corresponds to an SF Symbol icon
        var iconName: String {
            switch self {
            case .name: return "textformat.abc"
            case .scope: return "scope"
            case .agent: return "cpu"
            case .usage: return "chart.bar.xaxis"
            }
        }

        /// Direction applied when the user switches to this field.
        var defaultDirection: SortDirection {
            switch self {
            case .usage: return .descending
            default: return .ascending
            }
        }
    }

    /// Reference to global SkillManager (dependency injection)
    let skillManager: SkillManager

    init(skillManager: SkillManager) {
        self.skillManager = skillManager
    }

    // MARK: - Usage Scope

    /// Agents whose usage contributes to the current sort/badge.
    /// Unsupported Agents are excluded: `skillUsageScanState` reports their missing
    /// entry as `.notScanned`, which would otherwise make the list spin/freeze forever.
    var relevantUsageAgents: [AgentType] {
        let candidates = selectedAgentFilter.map { [$0] }
            ?? skillManager.skillUsageSupportedAgents
        return candidates.filter { skillManager.isSkillUsageSupported($0) }
    }

    var hasUnscannedRelevantUsage: Bool {
        relevantUsageAgents.contains {
            skillManager.skillUsageScanState(for: $0) == .notScanned
        }
    }

    var isRelevantUsageScanning: Bool {
        relevantUsageAgents.contains {
            skillManager.skillUsageScanState(for: $0) == .scanning
        }
    }

    /// True before or while the relevant scans finish; freezes ordering and shows a spinner.
    ///
    /// This intentionally ignores forced refreshes: when previous counts exist, the list must keep
    /// its current order and badges while new data is loading. Only first scans freeze the list.
    var isRelevantUsagePending: Bool {
        hasUnscannedRelevantUsage || isRelevantUsageScanning
    }

    /// True while a forced refresh for one of the relevant Agents is in flight. Separate from
    /// `isRelevantUsagePending` so ordering and badges stay stable during an in-place refresh.
    var isRelevantUsageRefreshing: Bool {
        relevantUsageAgents.contains { skillManager.isRefreshingSkillUsage($0) }
    }

    /// Whether the current scope has any Agent with a usage provider. When it is false, a manual
    /// refresh would be a no-op, so the toolbar hides the control instead of showing a dead button.
    var canRefreshRelevantUsage: Bool {
        !relevantUsageAgents.isEmpty
    }

    /// Failed log count restricted to the current scope, used by `isPartial`.
    var relevantUsageFailedLogCount: Int {
        relevantUsageAgents.reduce(0) { total, agent in
            switch skillManager.skillUsageScanState(for: agent) {
            case .available(_, _, let failed),
                 .stale(let failed),
                 .failed(let failed):
                return total + failed
            default:
                return total
            }
        }
    }

    /// Localization key for the unknown placeholder, also scoped to relevant Agents.
    var unknownUsageHelpKey: String {
        if isRelevantUsagePending { return L10nKeys.usageAgentScanning }
        if relevantUsageFailedLogCount > 0 { return L10nKeys.usageAgentUnreadable }
        return L10nKeys.usageAgentUnavailable
    }

    /// Aggregated usage for one skill, respecting the current Agent filter.
    /// Returns nil when no relevant Agent has readable usage history.
    func usageSummary(for skill: Skill) -> SkillUsageSummary? {
        var agentCounts: [AgentType: Int] = [:]

        for agent in relevantUsageAgents {
            switch skillManager.skillUsageScanState(for: agent) {
            case .available, .stale:
                // `.stale` keeps the previous readable snapshot, so its counts still participate
                // in sorting and badges. `isPartial` below carries the warning.
                agentCounts[agent] = skillManager.skillUsage(for: skill.id, agent: agent)?
                    .detectedInvocationCount ?? 0
            default:
                continue
            }
        }

        guard !agentCounts.isEmpty else { return nil }

        return SkillUsageSummary(
            count: agentCounts.values.reduce(0, +),
            agentCounts: agentCounts,
            isPartial: isRelevantUsagePending || relevantUsageFailedLogCount > 0
        )
    }

    // MARK: - Usage Refresh

    /// Minimum interval between automatic refreshes triggered by window activation.
    /// Manual refresh ignores this interval.
    static let usageAutoRefreshInterval: TimeInterval = 5 * 60

    /// Manually rescan usage for every Agent in the current scope.
    ///
    /// This ignores the automatic throttle; `SkillManager` deduplicates concurrent scans, and it
    /// refreshes the attempt timestamp so an automatic refresh will not immediately follow.
    func refreshRelevantUsage() async {
        let agents = Set(relevantUsageAgents)
        guard !agents.isEmpty else { return }
        await skillManager.loadSkillUsage(
            forceRefresh: true,
            agentTypes: agents
        )
    }

    /// Entry point for window activation and the initial Dashboard appearance.
    ///
    /// The authoritative throttle lives in `SkillManager.reserveAutomaticSkillUsageRefresh` so
    /// multiple windows cannot both pass it. The guards here are only cheap pre-checks to avoid
    /// main-actor work when a refresh obviously cannot start.
    ///
    /// - Parameter isDetailOpen: The split view keeps the Dashboard list visible while a skill
    ///   detail is open in the right pane. Automatic refresh is skipped then: activation should
    ///   not silently reshuffle the list the user is currently working from. Manual refresh
    ///   remains available because it is an explicit action.
    func autoRefreshRelevantUsage(
        now: Date = Date(),
        isDetailOpen: Bool = false
    ) async {
        guard !isDetailOpen else { return }
        guard sortOrder == .usage else { return }
        guard !relevantUsageAgents.isEmpty else { return }
        guard !isRelevantUsagePending, !isRelevantUsageRefreshing else { return }

        let reserved = skillManager.reserveAutomaticSkillUsageRefresh(
            agentTypes: Set(relevantUsageAgents),
            minimumInterval: Self.usageAutoRefreshInterval,
            now: now
        )
        guard !reserved.isEmpty else { return }

        await skillManager.loadSkillUsage(
            forceRefresh: true,
            agentTypes: reserved
        )
    }

    private func isOrderedBeforeByName(_ lhs: Skill, _ rhs: Skill) -> Bool {
        let lhsName = lhs.displayName.lowercased()
        let rhsName = rhs.displayName.lowercased()
        if lhsName != rhsName { return lhsName < rhsName }
        return lhs.id < rhs.id
    }

    /// Calculates the list of skills to display based on current search, filter, and sort conditions
    /// Computed property: dynamically calculated on each access, similar to Java getter
    var filteredSkills: [Skill] {
        var result = skillManager.skills

        // 1. Search filtering
        if !searchText.isEmpty {
            result = skillManager.search(query: searchText)
        }

        // 2. Agent filtering
        if let agent = selectedAgentFilter {
            result = result.filter { skill in
                skill.installations.contains { $0.agentType == agent }
            }
        }

        // 3. Sorting (ascending or descending based on sort direction)
        // In Swift closures, $0 and $1 are anonymous parameters, similar to Kotlin's it
        let ascending = sortDirection == .ascending
        switch sortOrder {
        case .name:
            result.sort {
                ascending
                    ? $0.displayName.lowercased() < $1.displayName.lowercased()
                    : $0.displayName.lowercased() > $1.displayName.lowercased()
            }
        case .scope:
            result.sort {
                ascending
                    ? $0.scope.displayName < $1.scope.displayName
                    : $0.scope.displayName > $1.scope.displayName
            }
        case .agent:
            // Agent Count defaults to descending (most first) for better visibility
            result.sort {
                ascending
                    ? $0.installations.count < $1.installations.count
                    : $0.installations.count > $1.installations.count
            }
        case .usage:
            // Freeze only while a relevant Agent is pending. Providers outside the current
            // filter may still be scanning in the background without reshuffling this view.
            guard !isRelevantUsagePending else {
                result.sort(by: isOrderedBeforeByName)
                break
            }

            // Precompute once: the comparator runs O(n log n) times.
            let counts = Dictionary(
                uniqueKeysWithValues: result.map { ($0.id, usageSummary(for: $0)?.count) }
            )

            result.sort { lhs, rhs in
                switch (counts[lhs.id] ?? nil, counts[rhs.id] ?? nil) {
                case let (lhsCount?, rhsCount?):
                    if lhsCount != rhsCount {
                        return ascending ? lhsCount < rhsCount : lhsCount > rhsCount
                    }
                case (nil, .some):
                    // Unknown usage always sorts after known values, in both directions.
                    return false
                case (.some, nil):
                    return true
                case (nil, nil):
                    break
                }
                return isOrderedBeforeByName(lhs, rhs)
            }
        }

        return result
    }

    /// Requests skill deletion (shows confirmation dialog first)
    func requestDelete(skill: Skill) {
        skillToDelete = skill
        showDeleteConfirmation = true
    }

    /// Confirms deletion
    func confirmDelete() async {
        guard let skill = skillToDelete else { return }
        do {
            try await skillManager.deleteSkill(skill)
        } catch {
            skillManager.errorMessage = "Delete failed: \(error.localizedDescription)"
        }
        skillToDelete = nil
        showDeleteConfirmation = false
    }

    /// Cancels deletion
    func cancelDelete() {
        skillToDelete = nil
        showDeleteConfirmation = false
    }

    // MARK: - Global Disable / Enable (context menu)

    /// Toggle disable/enable from the row's right-click menu.
    /// Only the id is forwarded — the direction is decided by `SkillManager` from `latest(id:)`,
    /// never from the view's `skill` snapshot. Errors go to `skillManager.errorMessage` so the
    /// Dashboard's bottom overlay shows them (same channel as `confirmDelete`).
    func toggleSkillDisabled(id: String) async {
        do {
            try await skillManager.toggleSkillDisabled(id: id)
        } catch {
            skillManager.errorMessage = error.localizedDescription
        }
    }

    /// Reinstall a broken skill from the row's right-click menu.
    /// The broken-row menu lives in DashboardView, so it needs this VM method (the detail VM's
    /// `reinstallBrokenSkill` is not reachable from here).
    func reinstallBrokenSkill(_ skill: Skill) async {
        do {
            try await skillManager.reinstallBrokenSkill(skill)
        } catch {
            skillManager.errorMessage = error.localizedDescription
        }
    }
}
