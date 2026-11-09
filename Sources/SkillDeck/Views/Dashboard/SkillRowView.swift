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

    /// Get SkillManager from environment for reading updateStatuses dictionary
    /// @Environment is SwiftUI's dependency injection mechanism (similar to Spring's @Autowired)
    @Environment(SkillManager.self) private var skillManager
    @Environment(\.localizationBundle) private var localizationBundle
    @Environment(\.locale) private var locale

    /// `Skill ==` compares only `id`, so the `skill` argument this row was built with can be a
    /// stale snapshot after a watcher refresh. Always read the flags from the manager's current
    /// array (same `latest(id:)` path used by every other view).
    private var isDisabled: Bool { skillManager.latest(id: skill.id)?.isDisabled ?? false }
    private var isBroken: Bool { skillManager.latest(id: skill.id)?.isBroken ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // First row: name + badges
            HStack {
                Text(skill.displayName).appFont(.headline)

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
                HStack(spacing: 4) {
                    ForEach(skill.installations) { installation in
                        AgentIconView(agentType: installation.agentType, size: 13)
                            .foregroundStyle(Constants.AgentColors.color(for: installation.agentType))
                            // Reduce opacity for inherited installation icons to visually distinguish from direct installations
                            .opacity(installation.isTrulyInherited ? 0.4 : 1.0)
                            // Hover tooltip: inherited installation shows "Copilot CLI (via ~/.claude/skills)"
                            .help(installation.isTrulyInherited
                                ? "\(installation.agentType.displayName) (via \(installation.parentDirectoryDisplayPath))"
                                : installation.agentType.displayName)
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

            // Third row: author + version + source
            HStack(spacing: 12) {
                if let author = skill.metadata.author {
                    Label(author, systemImage: "person").appFont(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let version = skill.metadata.version {
                    Label("v\(version)", systemImage: "tag").appFont(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let lockEntry = skill.lockEntry {
                    Label(lockEntry.source, systemImage: "link").appFont(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        // A disabled / broken skill stays in the list (for quick A/B) but is visually de-emphasized.
        .opacity(isDisabled || isBroken ? 0.5 : 1)
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
