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
                /// Check if this is a Codex canonical installation
                /// Codex's skillsDirectoryURL shares the same directory as canonical,
                /// so its installation record is isSymlink: false original file, should not be toggled
                let isCodexCanonical = agentType == .codex && isInstalled && !(installation?.isSymlink ?? true)
                let agent = skillManager.agents.first { $0.type == agentType }
                let isAgentAvailable = agent?.isInstalled == true || agent?.configDirectoryExists == true

                HStack {
                    Image(systemName: agentType.iconName)
                        .foregroundStyle(Constants.AgentColors.color(for: agentType))
                        .frame(width: 20)

                    Text(agentType.displayName)

                    Spacer()

                    // Inherited installation hint text: shows source path like "via ~/.claude/skills"
                    // Consistent with Codex canonical's "via ~/.agents/skills" style
                    if isInherited, let sourceAgent = installation?.inheritedFrom {
                        Text("via \(sourceAgent.skillsDirectoryPath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Codex canonical installation hint text:
                    // Consistent with inherited installation's "via ~/.claude/skills" style, indicating source directory
                    // Codex reads directly from ~/.agents/skills/, all canonical skills are naturally available
                    if isCodexCanonical {
                        Text("via ~/.agents/skills")
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
                    // - Codex canonical installation cannot be operated (delete should use deleteSkill)
                    // - Agent not installed and this skill not installed
                    .disabled(isInherited || isCodexCanonical || (!isAgentAvailable && !isInstalled))
                }
                .padding(.vertical, 2)
            }
        }
    }
}
