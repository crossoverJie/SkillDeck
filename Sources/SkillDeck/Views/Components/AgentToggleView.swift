import SwiftUI

/// AgentToggleView 显示 skill 在各 Agent 上的安装状态开关（F06）
///
/// 每个 Agent 一个 Toggle（开关），打开时创建 symlink，关闭时删除
struct AgentToggleView: View {

    let skill: Skill
    let viewModel: SkillDetailViewModel
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        VStack(spacing: 8) {
            ForEach(AgentType.allCases) { agentType in
                let isInstalled = skill.installations.contains { $0.agentType == agentType }
                let agent = skillManager.agents.first { $0.type == agentType }
                let isAgentAvailable = agent?.isInstalled == true || agent?.configDirectoryExists == true

                HStack {
                    Image(systemName: agentType.iconName)
                        .foregroundStyle(Constants.AgentColors.color(for: agentType))
                        .frame(width: 20)

                    Text(agentType.displayName)

                    Spacer()

                    if !isAgentAvailable {
                        Text("Not installed")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // Toggle 是 macOS 的开关控件（类似 Android 的 Switch）
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
                    .disabled(!isAgentAvailable && !isInstalled)
                }
                .padding(.vertical, 2)
            }
        }
    }
}
