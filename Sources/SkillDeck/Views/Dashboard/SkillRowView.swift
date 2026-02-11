import SwiftUI

/// SkillRowView 是列表中每一行的 skill 卡片
///
/// 显示 skill 名称、描述、scope 徽章、已安装的 Agent 图标
struct SkillRowView: View {

    let skill: Skill

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 第一行：名称 + 徽章
            HStack {
                Text(skill.displayName)
                    .font(.headline)

                ScopeBadge(scope: skill.scope)

                Spacer()

                // 已安装的 Agent 图标行
                HStack(spacing: 4) {
                    ForEach(skill.installedAgents, id: \.self) { agentType in
                        Image(systemName: agentType.iconName)
                            .font(.caption)
                            .foregroundStyle(Constants.AgentColors.color(for: agentType))
                            .help(agentType.displayName)  // hover 提示
                    }
                }
            }

            // 第二行：描述（最多显示两行）
            if !skill.metadata.description.isEmpty {
                Text(skill.metadata.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // 第三行：作者 + 版本 + 来源
            HStack(spacing: 12) {
                if let author = skill.metadata.author {
                    Label(author, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let version = skill.metadata.version {
                    Label("v\(version)", systemImage: "tag")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let lockEntry = skill.lockEntry {
                    Label(lockEntry.source, systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
