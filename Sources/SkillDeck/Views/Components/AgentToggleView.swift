import SwiftUI

/// AgentToggleView displays installation status toggles for skill on each Agent (F06)
///
/// One Toggle per Agent (switch), creates symlink when on, deletes when off
/// Toggle for inherited installation (isInherited) shows as ON but disabled, with source hint
/// For Codex: skill in ~/.agents/skills/ is native support, always ON and disabled
struct AgentToggleView: View {

    let skillID: String
    let viewModel: SkillDetailViewModel
    @Environment(SkillManager.self) private var skillManager

    /// Get the latest skill data from SkillManager to ensure UI reflects current state
    private var skill: Skill? {
        skillManager.skills.first { $0.id == skillID }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Use skill from SkillManager directly to ensure real-time updates
            if let skill = skill {
                ForEach(AgentType.allCases) { agentType in
                    AgentToggleRow(
                        agentType: agentType,
                        skill: skill,
                        viewModel: viewModel
                    )
                }
            }
        }
    }
}

/// Single row for an Agent toggle
private struct AgentToggleRow: View {
    let agentType: AgentType
    let skill: Skill
    let viewModel: SkillDetailViewModel
    @Environment(SkillManager.self) private var skillManager

    /// Find installation record for this Agent
    private var installation: SkillInstallation? {
        skill.installations.first { $0.agentType == agentType }
    }

    /// Whether this Agent has the skill installed
    private var isInstalled: Bool {
        installation != nil
    }

    /// Check if this is an inherited installation
    /// For Codex: reading from ~/.agents/skills/ is native support, not inheritance
    private var isInherited: Bool {
        guard let installation = installation else {
            return false
        }
        // Codex accessing ~/.agents/skills/ is native support, not inheritance
        if agentType == .codex && installation.inheritedFrom == .codex {
            return false
        }
        return installation.isInherited
    }

    /// Check if this is Codex native support (skill in ~/.agents/skills/)
    /// Native support means the skill is in Codex's official user-level directory
    private var isCodexNativeSupport: Bool {
        guard agentType == .codex else { return false }
        guard let installation = installation else { return false }
        // Native support: skill is in ~/.agents/skills/ (Codex's official directory)
        return installation.inheritedFrom == .codex
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
        // - Codex native support (always on, cannot be toggled)
        isInherited || isCodexNativeSupport || (!isAgentAvailable && !isInstalled)
    }

    var body: some View {
        HStack {
            Image(systemName: agentType.iconName)
                .foregroundStyle(Constants.AgentColors.color(for: agentType))
                .frame(width: 20)

            Text(agentType.displayName)

            Spacer()

            // Hint text for special states
            if isCodexNativeSupport {
                // Codex native support: skill is in ~/.agents/skills/
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
                        await viewModel.toggleAgent(agentType, for: skill)
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(isToggleDisabled)
        }
        .padding(.vertical, 2)
    }
}
