import SwiftUI

/// SkillRowView is the skill card for each row in the list
///
/// Displays skill name, description, scope badge, and installed Agent icons
struct SkillRowView: View {

    let skill: Skill

    var usageSummary: SkillUsageSummary? = nil
    var showsUnknownUsage: Bool = false
    /// True when a relevant Agent is unscanned/scanning. This is scope-aware:
    /// do not read the global `skillManager.isScanningSkillUsage` here.
    var usageIsScanning: Bool = false
    /// Locale key chosen by the ViewModel for the unknown placeholder
    /// (scanning / unreadable / no local history).
    var unknownUsageHelpKey: String = L10nKeys.usageAgentUnavailable
    /// Whether the third row shows `lockEntry.source`.
    ///
    /// Set to `false` in grouped mode: the section header already states the source, and
    /// repeating it inside every row is noise. The `= true` default keeps every other call site
    /// source-compatible (a defaulted parameter does not break existing memberwise calls).
    var showsSource: Bool = true

    /// Get SkillManager from environment for reading updateStatuses dictionary
    /// @Environment is SwiftUI's dependency injection mechanism (similar to Spring's @Autowired)
    @Environment(SkillManager.self) private var skillManager
    @Environment(\.localizationBundle) private var localizationBundle
    @Environment(\.locale) private var locale

    /// Maximum number of Agent icons rendered inline before the rest collapse into a "+N" counter.
    ///
    /// `static` (not an instance property) on purpose: instance stored properties take part in the
    /// synthesized memberwise initializer, and a `private` one would make that initializer private,
    /// breaking `SkillRowView(...)` calls from DashboardView. A `private static let` is never part of
    /// the memberwise init, so it is safe here.
    private static let maxVisibleAgentIcons = 5

    /// `Skill ==` compares only `id`, so the `skill` argument this row was built with can be a
    /// stale snapshot after a watcher refresh. Always read the flags from the manager's current
    /// array (same `latest(id:)` path used by every other view).
    private var isDisabled: Bool { skillManager.latest(id: skill.id)?.isDisabled ?? false }
    private var isBroken: Bool { skillManager.latest(id: skill.id)?.isBroken ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // First row: name + badges
            HStack {
                // `.lineLimit(1)` stops the name from wrapping onto a second line (the old
                // behaviour without it: SwiftUI lets the flexible Text wrap when the row is tight).
                // `.truncationMode(.middle)` keeps both the identifiable head and the meaningful
                // tail (e.g. "test-driven-development") visible when the name must be shortened.
                // `.help(...)` compensates for the truncation: hovering shows the full name.
                // `.layoutPriority(1)` makes the name win the available width over the trailing
                // badges/icon cluster instead of being the first thing squeezed.
                Text(skill.displayName)
                    .appFont(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(skill.displayName)
                    .layoutPriority(1)

                ScopeBadge(scope: skill.scope)

                // Disabled / broken badge. Broken takes priority over disabled (a broken skill
                // has no marker, so it is never `isDisabled`).
                if isBroken {
                    SkillStatusBadge(
                        text: localized(L10nKeys.skillBrokenBadge),
                        systemImage: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                } else if isDisabled {
                    SkillStatusBadge(
                        text: localized(L10nKeys.skillDisabledBadge),
                        systemImage: "eye.slash",
                        color: .gray
                    )
                }

                // F12: Display different indicator icons based on update check status.
                // Hidden while disabled / broken so a stale "has update" arrow cannot imply the
                // skill is active (updateStatuses is also reset to .notChecked on toggle).
                if !isDisabled && !isBroken {
                    updateStatusIndicator
                }

                usageBadge

                Spacer()

                // Installed Agent icon row
                // Use installations instead of installedAgents to get isTrulyInherited information
                // Inherited installation icons have reduced opacity, hover tooltip shows source
                //
                // The cluster is capped at `Self.maxVisibleAgentIcons` icons: there are 14 Agent
                // types today, and rendering all of them costs ~240pt, which used to squeeze the
                // skill name into a second line even at a generous column width. Extras become a
                // "+N" counter whose tooltip lists every hidden Agent.
                HStack(spacing: 4) {
                    // `let` bindings inside a ViewBuilder are allowed (they are plain statements,
                    // not views); SwiftUI just ignores them when building the view tree.
                    let visible = skill.installations.prefix(Self.maxVisibleAgentIcons)
                    let hiddenCount = skill.installations.count - visible.count

                    // `visible` is an ArraySlice<SkillInstallation>; ForEach accepts any
                    // RandomAccessCollection of Identifiable elements, not only Array.
                    ForEach(visible) { installation in
                        AgentIconView(agentType: installation.agentType, size: 13)
                            .foregroundStyle(Constants.AgentColors.color(for: installation.agentType))
                            // Reduce opacity for inherited installation icons to visually distinguish from direct installations
                            .opacity(installation.isTrulyInherited ? 0.4 : 1.0)
                            .help(installationTooltip(installation))
                    }

                    if hiddenCount > 0 {
                        Text("+\(hiddenCount)")
                            .appFont(.caption2)
                            .foregroundStyle(.secondary)
                            .help(hiddenAgentsTooltip)
                    }
                }
                // The whole row is already dimmed to 0.5 below; do NOT add a second opacity here.
                // Stacking 0.5 × 0.3 would leave the icons at ~15% — effectively invisible.
                // Row-level dimming alone still reads as "frozen assignments".
            }

            // Second row: description (max 2 lines)
            if !skill.metadata.description.isEmpty {
                Text(skill.metadata.description).appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Third row: author + version + source.
            //
            // The WHOLE row is conditional, not just the source label: when everything else is
            // empty, an always-present `HStack` would still occupy one slot of the outer
            // `VStack(spacing: 6)`, adding 6pt of dead space to every grouped row and making
            // row heights uneven.
            let hasSourceRow = skill.metadata.author != nil
                || skill.metadata.version != nil
                || (showsSource && skill.lockEntry != nil)

            if hasSourceRow {
                HStack(spacing: 12) {
                    if let author = skill.metadata.author {
                        Label(author, systemImage: "person").appFont(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if let version = skill.metadata.version {
                        Label("v\(version)", systemImage: "tag").appFont(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if showsSource, let lockEntry = skill.lockEntry {
                        Label(lockEntry.source, systemImage: "link").appFont(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        // A disabled / broken skill stays in the list (for quick A/B) but is visually de-emphasized.
        .opacity(isDisabled || isBroken ? 0.5 : 1)
    }

    // MARK: - Agent Icon Helpers

    /// Hover tooltip for a single Agent icon.
    /// An inherited installation names the directory it actually reads from, e.g.
    /// "Copilot CLI (via ~/.claude/skills)".
    private func installationTooltip(_ installation: SkillInstallation) -> String {
        installation.isTrulyInherited
            ? "\(installation.agentType.displayName) (via \(installation.parentDirectoryDisplayPath))"
            : installation.agentType.displayName
    }

    /// Hover tooltip for the "+N" counter: lists the Agents that were collapsed away,
    /// one per line, using the same wording as the individual icons.
    private var hiddenAgentsTooltip: String {
        skill.installations
            .dropFirst(Self.maxVisibleAgentIcons)
            .map(installationTooltip)
            .joined(separator: "\n")
    }

    // MARK: - Update Status Indicator

    /// Renders different status indicators based on SkillUpdateStatus enum
    ///
    /// @ViewBuilder allows using conditional branches in computed properties to return different View types,
    /// the compiler automatically wraps them into concrete types of `some View` (similar to Java generics type erasure but resolved at compile time).
    /// Uses `switch` to exhaustively enumerate all enum cases (Swift enforces exhaustive matching, similar to Rust's match).
    @ViewBuilder
    private var updateStatusIndicator: some View {
        switch skillManager.updateStatuses[skill.id] ?? .notChecked {
        case .notChecked:
            // Default state: display nothing
            // EmptyView() is SwiftUI's empty view placeholder, takes no space
            EmptyView()
        case .checking:
            // Checking: display spinning progress indicator (ProgressView)
            // .controlSize(.mini) makes spinner smaller, suitable for inline display
            ProgressView()
                .controlSize(.mini)
        case .hasUpdate:
            // Update available: orange up arrow in filled circle icon
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.orange).appFont(.caption)
                .help("Update available")
        case .upToDate:
            // Up to date: green checkmark in filled circle icon
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green).appFont(.caption)
                .help("Up to date")
        case .error(let message):
            // Check failed: yellow warning triangle icon, hover shows error details
            // .help() sets mouse hover tooltip (native macOS feature)
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow).appFont(.caption)
                .help("Check failed: \(message)")
        }
    }

    // MARK: - Usage Badge

    /// Detected invocation count for the current Dashboard scope.
    ///
    /// Unknown usage is rendered as an em dash rather than `0` so "not scanned" and "never used"
    /// never look alike. The tooltip details use the same scope as the number.
    @ViewBuilder
    private var usageBadge: some View {
        if let summary = usageSummary {
            HStack(spacing: 3) {
                Image(systemName: "chart.bar.xaxis")
                Text(String(format: localized(L10nKeys.usageAgentUsesFormat), summary.count))
                if summary.isPartial {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(localized(L10nKeys.usageIncompleteHelp))
                }
            }
            .appFont(.caption)
            .foregroundStyle(.secondary)
            .help(usageTooltip(summary))
        } else if showsUnknownUsage {
            if usageIsScanning {
                ProgressView().controlSize(.mini)
            } else {
                Text("—")
                    .appFont(.caption)
                    .foregroundStyle(.tertiary)
                    .help(localized(unknownUsageHelpKey))
            }
        }
    }

    private func usageTooltip(_ summary: SkillUsageSummary) -> String {
        let lines = summary.agentCounts
            .sorted {
                ($0.key.displayName, $0.key.rawValue)
                    < ($1.key.displayName, $1.key.rawValue)
            }
            .map { agent, count in
                "\(agent.displayName): \(String(format: localized(L10nKeys.usageAgentUsesFormat), count))"
            }

        var parts = [lines.joined(separator: "\n"), localized(L10nKeys.usageCaveat)]
        if summary.isPartial {
            parts.append(localized(L10nKeys.usageIncompleteHelp))
        }
        return parts.joined(separator: "\n\n")
    }

    private func localized(_ key: String) -> String {
        L10n.string(key, bundle: localizationBundle, locale: locale)
    }
}
