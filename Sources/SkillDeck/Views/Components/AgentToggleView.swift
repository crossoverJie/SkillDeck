import SwiftUI

/// AgentToggleView 显示 skill 在各 Agent 上的安装状态开关（F06）
///
/// 每个 Agent 一个 Toggle（开关），打开时创建 symlink，关闭时删除
/// 继承安装（isInherited）的 Toggle 显示为 ON 但 disabled，并带有来源提示
struct AgentToggleView: View {

    let skill: Skill
    let viewModel: SkillDetailViewModel
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        VStack(spacing: 8) {
            ForEach(AgentType.allCases) { agentType in
                /// 查找该 Agent 对应的安装记录（可能是直接安装或继承安装）
                let installation = skill.installations.first { $0.agentType == agentType }
                let isInstalled = installation != nil
                /// 检查是否为继承安装（来自其他 Agent 的目录）
                let isInherited = installation?.isInherited ?? false
                let agent = skillManager.agents.first { $0.type == agentType }
                let isAgentAvailable = agent?.isInstalled == true || agent?.configDirectoryExists == true

                HStack {
                    Image(systemName: agentType.iconName)
                        .foregroundStyle(Constants.AgentColors.color(for: agentType))
                        .frame(width: 20)

                    Text(agentType.displayName)

                    Spacer()

                    // 继承安装的提示文字：显示 "via Claude Code" 等来源信息
                    // 告知用户该安装来自其他 Agent，需到源 Agent 处才能修改
                    if isInherited, let sourceAgent = installation?.inheritedFrom {
                        Text("via \(sourceAgent.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !isAgentAvailable && !isInstalled {
                        Text("Not installed")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // Toggle 是 macOS 的开关控件（类似 Android 的 Switch）
                    // 继承安装时：Toggle 显示为 ON 但 disabled，防止用户误操作
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
                    // disabled 条件：继承安装不可操作 || Agent 未安装且未安装此 skill
                    .disabled(isInherited || (!isAgentAvailable && !isInstalled))
                }
                .padding(.vertical, 2)
            }
        }
    }
}
