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

    /// Product default: grouped view. Flipping this ONE line to `.none` restores the old
    /// flat list, which is also the documented rollback path (see the plan's §6).
    ///
    /// Not persisted (neither is `sortOrder`), so every launch starts grouped.
    var groupMode: GroupMode = .source

    /// Section ids (`SkillGroup.id`) the user has collapsed.
    ///
    /// A `Set<String>` rather than a flag on `SkillGroup`: the groups themselves are recomputed
    /// on every body evaluation, so state that must survive re-derivation belongs to the
    /// ViewModel. Keyed by the stable group id (e.g. "github:obra/superpowers"), so collapsing
    /// survives sorting changes and refreshes, and a group that disappears because of a filter
    /// comes back collapsed.
    var collapsedGroupIDs: Set<String> = []

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
    }

    /// Sort order enum
    ///
    /// No `String` raw value any more: the display text now comes from localized keys
    /// (`titleKey`) instead of a hard-coded English literal, and nothing read `rawValue`
    /// (it was never `Codable`).
    enum SortOrder: CaseIterable {
        case name
        case scope
        case agent
        case usage

        /// Localization key for the menu row and the toolbar label. Same rationale as
        /// `GroupMode.titleKey`: resolution happens in the View, which owns bundle + locale.
        var titleKey: String {
            switch self {
            case .name: return L10nKeys.dashboardSortName
            case .scope: return L10nKeys.dashboardSortScope
            case .agent: return L10nKeys.dashboardSortAgentCount
            case .usage: return L10nKeys.dashboardSortUsageCount
            }
        }

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

    /// How the Dashboard list is segmented.
    ///
    /// Orthogonal to `SortOrder`: grouping decides WHERE a skill appears, sorting decides the
    /// order INSIDE a group (and, indirectly, the order of the groups themselves).
    ///
    /// Note for readers coming from Java/Go: this is a plain case-only enum (no raw values) —
    /// Swift lets it still conform to `CaseIterable` and to `Equatable`/`Hashable` for free, so
    /// it can be used directly as a `ForEach(id: \.self)` element.
    enum GroupMode: CaseIterable {
        /// One section per install source (repo / local path / ClawHub).
        case source
        /// Legacy flat list: exactly what the Dashboard rendered before grouping existed.
        case none

        /// SF Symbol shown next to the menu row.
        var iconName: String {
            switch self {
            case .source: return "square.stack.3d.down.right"
            case .none: return "list.bullet"
            }
        }

        /// Localization key for the menu row. Kept as a *key* (not a resolved string) for the
        /// same reason `unknownUsageHelpKey` is a key: the ViewModel has no bundle/locale
        /// environment, so it cannot resolve localized text itself.
        var titleKey: String {
            switch self {
            case .source: return L10nKeys.dashboardGroupSource
            case .none: return L10nKeys.dashboardGroupNone
            }
        }
    }

    /// Where a section header's text comes from.
    ///
    /// An enum instead of two mutually exclusive optionals: the "exactly one of these is set"
    /// invariant is expressed by the type itself, so no `assert` and no force-unwrap is needed.
    /// `Equatable` is synthesized (neither case carries a non-Equatable payload), which lets
    /// tests write `XCTAssertEqual(group.title, .literal("obra/superpowers"))`.
    enum GroupTitle: Equatable {
        /// Literal text taken from the data, e.g. "obra/superpowers" or "ClawHub".
        case literal(String)
        /// Localization key resolved by the View (e.g. the "no source recorded" bucket).
        case localized(String)
    }

    /// One rendered section of the Dashboard list.
    ///
    /// `Identifiable` because `ForEach` needs stable identity: the string key derived from the
    /// lock entry survives refreshes, whereas an array index would make SwiftUI animate rows
    /// wrongly whenever the sort order changes.
    struct SkillGroup: Identifiable {
        /// Stable identity, e.g. "github:obra/superpowers", "path:/users/x/repo",
        /// "marketplace:clawhub".
        let id: String
        let title: GroupTitle
        /// Optional tooltip: full local path, marketplace hint, ...
        let helpText: String?
        /// Members, already ordered by the active SortOrder/SortDirection.
        let skills: [Skill]
        /// Browser-openable page for this source (GitHub repo today). `nil` when the source has
        /// no meaningful web page (local path, ClawHub slug, unknown source).
        ///
        /// Held here rather than recomputed in the View so the SSH-vs-HTTPS normalization lives
        /// next to the other `source` parsing and stays unit-testable.
        let webURL: URL?
    }

    /// Where a single skill's section identity comes from.
    ///
    /// Internal (not `private`) so `@testable import` can drive `sourceDescriptor(for:)`
    /// directly from tests.
    struct SourceDescriptor {
        /// Section identity, e.g. "github:obra/superpowers".
        let key: String
        /// Header derived from THIS skill alone. For github groups this is only a fallback: the
        /// group-wide `preferredVariant(...)` vote replaces it once every member is known.
        let title: GroupTitle
        /// Optional tooltip (full local path, ...). Taken from the group's first member.
        let helpText: String?
        /// The raw casing of a github `source`, fed into `preferredVariant`. `nil` for every
        /// other kind of group (there is nothing to vote on).
        let variant: String?
        /// Browser-openable page for this source, when one exists.
        let webURL: URL?
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

    // MARK: - Source Grouping

    /// Groups an already-sorted skill array into sections.
    ///
    /// Deterministic given (`groupMode`, input order): it deliberately does NOT read
    /// `filteredSkills` internally, so the View can pass the ONE snapshot it already computed
    /// for the empty-state check. Reading `filteredSkills` here instead would sort the whole
    /// array twice per body evaluation (and, under `.usage`, precompute `usageSummary` twice).
    ///
    /// Implementation note for readers coming from Java/Go: this is a single pass with a
    /// first-appearance list `order` plus two dictionaries. That is cheaper and simpler than
    /// `Dictionary(grouping:)` followed by a second sort, and it DEFINES the group order as
    /// "the position of the group's highest-ranked skill in the current sort". No extra
    /// ordering knob to explain, persist, or get out of sync with `sortOrder`.
    func sourceGroups(from skills: [Skill]) -> [SkillGroup] {
        // Defensive only: the `.none` branch of the View keeps the untouched flat `List` and
        // never calls this. Returning [] (rather than a fake single group) makes a future
        // wiring mistake loud instead of silently rendering an ungrouped list through a
        // section code path.
        guard groupMode == .source else { return [] }

        var order: [String] = []
        var members: [String: [Skill]] = [:]
        var variants: [String: [String: Int]] = [:]   // key -> (source casing -> occurrences)

        for skill in skills {
            let descriptor = Self.sourceDescriptor(for: skill)
            if members[descriptor.key] == nil { order.append(descriptor.key) }
            members[descriptor.key, default: []].append(skill)
            if let variant = descriptor.variant {
                variants[descriptor.key, default: [:]][variant, default: 0] += 1
            }
        }

        return order.compactMap { key in
            guard let groupSkills = members[key] else { return nil }
            let first = Self.sourceDescriptor(for: groupSkills[0])

            // Only `.literal` headers can be re-cased (the localized buckets carry no fallback
            // text). WITHOUT this override the header is "whichever casing the currently first
            // member happens to carry", i.e. it silently changes when the sort order changes —
            // and the `variants` vote above would be a dead computation.
            let title: GroupTitle
            if case .literal(let fallback) = first.title {
                title = .literal(Self.preferredVariant(variants[key] ?? [:], fallback: fallback))
            } else {
                title = first.title
            }

            return SkillGroup(
                id: key,
                title: title,
                helpText: first.helpText,
                skills: groupSkills,
                webURL: first.webURL
            )
        }
    }

    /// Whether a section is currently collapsed.
    func isGroupCollapsed(_ groupID: String) -> Bool {
        collapsedGroupIDs.contains(groupID)
    }

    /// Flip one section between collapsed and expanded.
    ///
    /// Only updates the `Set`; the View derives the visible rows from it, so this stays a pure
    /// state mutation (no fs/network work, safe to call from a tap gesture in `body`).
    func toggleGroupCollapsed(_ groupID: String) {
        if collapsedGroupIDs.contains(groupID) {
            collapsedGroupIDs.remove(groupID)
        } else {
            collapsedGroupIDs.insert(groupID)
        }
    }

    /// Where a single skill's section identity comes from.
    ///
    /// The FIRST dispatch is `sourceType`, never `source.contains("/")`: a ClawHub slug can
    /// legitimately contain a slash, so sniffing the string would misfile it as a repo.
    /// Every branch trims `source` first, and the final catch-all is what keeps a
    /// `sourceType == "github"` entry with an empty `source` from falling through the cracks.
    static func sourceDescriptor(for skill: Skill) -> SourceDescriptor {
        guard let entry = skill.lockEntry else {
            return SourceDescriptor(
                key: "unknown:no-entry",
                title: .localized(L10nKeys.dashboardGroupUnknownSource),
                helpText: nil,
                variant: nil,
                webURL: nil
            )
        }

        let trimmedSource = entry.source.trimmingCharacters(in: .whitespacesAndNewlines)

        switch entry.sourceType {
        case "github" where !trimmedSource.isEmpty:
            // Group key is case-insensitive (`crossoverJie/skills` and `crossoverjie/skills`
            // must merge), while the header casing is decided by a group-wide vote in
            // `sourceGroups(from:)`. Here we only supply the first-seen casing as fallback.
            return SourceDescriptor(
                key: "github:" + trimmedSource.lowercased(),
                title: .literal(trimmedSource),
                helpText: nil,
                variant: trimmedSource,
                webURL: githubWebURL(source: trimmedSource, sourceUrl: entry.sourceUrl)
            )

        case "local" where !trimmedSource.isEmpty:
            // `standardizedFileURL` removes `./`, `..` and trailing slashes WITHOUT touching
            // the disk. `resolvingSymlinksInPath()` would do I/O, and this runs on every body
            // evaluation, so it is out of the question here.
            let normalizedPath = URL(fileURLWithPath: trimmedSource).standardizedFileURL.path
            return SourceDescriptor(
                // Lower-cased key: macOS filesystems are case-insensitive by default, so
                // `/Users/x/repo-a` and `/users/x/repo-a` are the same directory. The tooltip
                // keeps the original casing because it is meant for a human to read.
                key: "path:" + normalizedPath.lowercased(),
                title: .literal(URL(fileURLWithPath: normalizedPath).lastPathComponent),
                helpText: normalizedPath,
                variant: nil,
                // A local repository may have a remote, but resolving it would need git I/O on
                // every body evaluation. No button is better than a wrong guess.
                webURL: nil
            )

        case "clawhub":
            // ClawHub writes one source per skill (the slug), so grouping by source would give
            // every ClawHub skill its own section titled with its own name. One fixed bucket.
            return SourceDescriptor(
                key: "marketplace:clawhub",
                title: .literal("ClawHub"),
                helpText: nil,
                variant: nil,
                webURL: nil
            )

        case _ where !trimmedSource.isEmpty:
            // Unknown `sourceType` may come from historical / hand-edited CommitHashCache JSON
            // (`SkillManager` copies `linked.sourceType` verbatim). Keeping each source in its
            // own group preserves its tooltip instead of swallowing it into the fallback bucket.
            return SourceDescriptor(
                key: "unknown:" + trimmedSource.lowercased(),
                title: .literal(trimmedSource),
                helpText: nil,
                // Also vote on casing: two unknown sources differing only in case collapse
                // into one group, and without a variant the header would be "whichever member
                // ranks first", i.e. it would change when the sort order changes.
                variant: trimmedSource,
                // Not known to be a repo, so do not offer a "open on the web" button.
                webURL: nil
            )

        default:
            // Catch-all: `github`/`local` with an empty source, a known type with an empty
            // source, or anything else unforeseen.
            return SourceDescriptor(
                key: "unknown:no-entry",
                title: .localized(L10nKeys.dashboardGroupUnknownSource),
                helpText: nil,
                variant: nil,
                webURL: nil
            )
        }
    }

    /// Browser-openable GitHub URL for a `source` such as `crossoverJie/skills`.
    ///
    /// The lock file stores whatever git used: `https://github.com/o/r.git` most of the time,
    /// but SSH (`git@github.com:o/r.git`) also appears in real data, and that form cannot be
    /// opened in a browser. So: accept `sourceUrl` only when it is HTTP(S), otherwise rebuild
    /// the canonical web URL from `owner/repo`, stripping any `.git` suffix.
    static func githubWebURL(source: String, sourceUrl: String) -> URL? {
        /// Trim, drop a `.git` suffix, and keep the result only if it is a clean http(s) URL.
        func normalized(_ raw: String) -> URL? {
            var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasSuffix(".git") { text.removeLast(4) }
            guard let url = URL(string: text),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http",
                  url.host != nil,
                  // Reject userinfo (`https://github.com@evil.example/x`): the tooltip claims
                  // github.com while the browser would go somewhere else. A lock file is local
                  // data, but a hand-edited or maliciously supplied entry must not be able to
                  // turn this button into a mislabeled redirect.
                  url.user == nil
            else { return nil }
            return url
        }

        return normalized(sourceUrl) ?? normalized("https://github.com/\(source)")
    }

    /// Deterministic tie-break for "the same repo, two casings":
    /// most frequent → most uppercase letters (so `crossoverJie/skills` beats
    /// `crossoverjie/skills`) → lexicographic.
    ///
    /// `static` (not `private`) on purpose: `@testable import` cannot see `private` members, and
    /// this rule is exactly the kind of thing that should be pinned by a unit test.
    static func preferredVariant(_ counts: [String: Int], fallback: String) -> String {
        counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            let lhsUpper = lhs.key.reduce(0) { $1.isUppercase ? $0 + 1 : $0 }
            let rhsUpper = rhs.key.reduce(0) { $1.isUppercase ? $0 + 1 : $0 }
            if lhsUpper != rhsUpper { return lhsUpper < rhsUpper }
            // `max(by:)` keeps the element for which the predicate is false, i.e. the
            // "greater" one, so invert the comparison to make the lexicographically
            // SMALLER key win on a full tie.
            return lhs.key > rhs.key
        }?.key ?? fallback
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
