import SwiftUI

/// AgentToggleView displays installation status toggles for skill on each Agent (F06)
///
/// One Toggle per Agent (switch), creates symlink when on, deletes when off
/// Toggle for inherited installation (isInherited) shows as ON but disabled, with source hint
struct AgentToggleView: View {

    let skill: Skill
    let viewModel: SkillDetailViewModel
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        VStack(spacing: 8) {
            ForEach(AgentType.allCases) { agentType in
                /// Find installation record for this Agent (may be direct installation or inherited)
                let installation = skill.installations.first { $0.agentType == agentType }
                let isInstalled = installation != nil
                /// Check if this is an inherited installation (from another Agent's directory)
                let isInherited = installation?.isInherited ?? false
                let agent = skillManager.agents.first { $0.type == agentType }
                let isAgentAvailable = agent?.isInstalled == true || agent?.configDirectoryExists == true

                HStack {
                    Image(systemName: agentType.iconName)
                        .foregroundStyle(Constants.AgentColors.color(for: agentType))
                        .frame(width: 20)

                    Text(agentType.displayName)

                    Spacer()

                    // Inherited installation hint text: shows source path like "via ~/.claude/skills"
                    // Uses parentDirectoryDisplayPath derived from the actual installation path
                    if isInherited, let installation {
                        Text("via \(installation.parentDirectoryDisplayPath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !isAgentAvailable && !isInstalled {
                        Text("Not installed")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // Toggle is macOS switch control (similar to Android's Switch)
                    // When inherited: Toggle shows as ON but disabled, preventing user mistakes
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
                    // disabled conditions:
                    // - Inherited installation cannot be operated (need to modify at source Agent)
                    // - Agent not installed and this skill not installed
                    .disabled(isInherited || (!isAgentAvailable && !isInstalled))
                }
                .padding(.vertical, 2)
            }
        }
    }
}
