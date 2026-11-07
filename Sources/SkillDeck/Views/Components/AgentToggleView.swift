import SwiftUI

/// AgentToggleView displays installation status toggles for skill on each Agent (F06)
///
/// One Toggle per Agent (switch), creates symlink when on, deletes when off
/// Toggle for inherited installation (isInherited) shows as ON but disabled, with source hint
/// For shared-directory Agents (Codex, Pi, ...): skill in ~/.agents/skills/ is native support, always ON and disabled
struct AgentToggleView: View {

    let skillID: String
    let viewModel: SkillDetailViewModel
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        VStack(spacing: 8) {
            // Iterate through all detected Agents
            ForEach(AgentType.allCases) { agentType in
                AgentToggleRow(
                    skillID: skillID,
                    agentType: agentType,
                    viewModel: viewModel
                )
            }
        }
    }
}

/// Single row for an Agent toggle
/// Uses skillID instead of Skill to ensure proper SwiftUI dependency tracking
private struct AgentToggleRow: View {
    let skillID: String
    let agentType: AgentType
    let viewModel: SkillDetailViewModel
    @Environment(SkillManager.self) private var skillManager
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle

    /// Get the latest skill data from SkillManager to ensure real-time updates
    /// Accessing skillManager.skills here ensures SwiftUI tracks this dependency
    private var skill: Skill? {
        skillManager.skills.first { $0.id == skillID }
    }

    /// Find installation record for this Agent
    private var installation: SkillInstallation? {
        skill?.installations.first { $0.agentType == agentType }
    }

    /// Whether this Agent has the skill installed
    private var isInstalled: Bool {
        installation != nil
    }

    /// Check if this is an inherited installation (from another Agent's directory)
    /// Uses isTrulyInherited which treats Codex's ~/.agents/skills/ as non-inherited
    private var isInherited: Bool {
        installation?.isTrulyInherited ?? false
    }

    /// Check if this is native shared-directory support (skill read from ~/.agents/skills/)
    /// Any Agent that natively reads the canonical store shows "Native support", not "via ..."
    private var isNativeSharedSupport: Bool {
        installation?.accessesCanonicalDirectoryNatively ?? false
    }

    /// Whether the Agent is available (installed or config exists)
    private var isAgentAvailable: Bool {
        let agent = skillManager.agents.first { $0.type == agentType }
        return agent?.isInstalled == true || agent?.configDirectoryExists == true
    }

    /// Whether the toggle should be disabled
    private var isToggleDisabled: Bool {
        // Disabled conditions:
        // - Inherited installation (need to modify at source Agent)
        // - Agent not installed and skill not installed
        // - Native shared-directory support (always on, cannot be toggled)
        isInherited || isNativeSharedSupport || (!isAgentAvailable && !isInstalled)
    }

    var body: some View {
        HStack {
            AgentIconView(agentType: agentType, size: 16)
                .foregroundStyle(Constants.AgentColors.color(for: agentType))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(agentType.displayName)
                usageSummary
            }

            Spacer()

            // Hint text for special states
            if isNativeSharedSupport {
                // Agent natively reads ~/.agents/skills/: always available
                Text("Native support").appFont(.caption)
                    .foregroundStyle(.secondary)
            } else if isInherited, let installation {
                // Inherited installation: shows source path like "via ~/.claude/skills"
                Text("via \(installation.parentDirectoryDisplayPath)").appFont(.caption)
                    .foregroundStyle(.secondary)
            } else if !isAgentAvailable && !isInstalled {
                Text("Not installed").appFont(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Toggle switch
            Toggle("", isOn: Binding(
                get: { isInstalled },
                set: { _ in
                    Task {
                        // Pass the current skill from SkillManager, not the captured value
                        if let skill = skillManager.skills.first(where: { $0.id == skillID }) {
                            await viewModel.toggleAgent(agentType, for: skill)
                        }
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(isToggleDisabled)
        }
        .padding(.vertical, 2)
    }

    /// Compact, read-only usage evidence under the Agent name.
    ///
    /// This intentionally renders nothing before a scan. Showing "0 uses" for an unscanned Agent
    /// would make "unknown" look like "never used".
    @ViewBuilder
    private var usageSummary: some View {
        if skillManager.isSkillUsageSupported(agentType) {
            switch skillManager.skillUsageScanState(for: agentType) {
            case .notScanned:
                EmptyView()

            case .scanning:
                LText(key: L10nKeys.usageAgentScanning)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)

            case .failed:
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    LText(key: L10nKeys.usageAgentUnreadable)
                }
                .appFont(.caption)
                .foregroundStyle(.orange)

            case .stale:
                // The latest refresh could not read history, but the manager kept the previous
                // snapshot. Show the count with a dedicated stale tooltip rather than hiding it.
                if let record = skillManager.skillUsage(for: skillID, agent: agentType) {
                    HStack(spacing: 4) {
                        Text(String(
                            format: localized(L10nKeys.usageAgentUsesFormat),
                            record.detectedInvocationCount
                        ))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .help(lastUsedHelp(record))

                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help(localized(L10nKeys.usageStaleHelp))
                    }
                } else {
                    LText(key: L10nKeys.usageAgentUnreadable)
                        .appFont(.caption)
                        .foregroundStyle(.orange)
                }

            case .unavailable:
                LText(key: L10nKeys.usageAgentUnavailable)
                    .appFont(.caption)
                    .foregroundStyle(.tertiary)

            case .available(_, let preservedLogCount, _):
                if let record = skillManager.skillUsage(for: skillID, agent: agentType) {
                    HStack(spacing: 4) {
                        Text(String(
                            format: localized(L10nKeys.usageAgentUsesFormat),
                            record.detectedInvocationCount
                        ))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .help(lastUsedHelp(record))

                        // Keep showing the last known count, but mark that it may come from
                        // the previous scan because this scan could not read the history.
                        if preservedLogCount > 0 {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help(localized(L10nKeys.usageIncompleteHelp))
                        }
                    }
                } else {
                    LText(key: L10nKeys.usageAgentNeverDetected)
                        .appFont(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func localized(_ key: String) -> String {
        L10n.string(key, bundle: localizationBundle, locale: locale)
    }

    private func lastUsedHelp(_ record: SkillUsageRecord) -> String {
        guard let lastDetectedAt = record.lastDetectedAt else {
            return localized(L10nKeys.usageCaveat)
        }

        let date = lastDetectedAt.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)
        )
        return String(format: localized(L10nKeys.usageAgentLastUsedFormat), date)
    }
}
