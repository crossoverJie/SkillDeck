import SwiftUI

/// AgentBadgeView 显示一个 Agent 的小徽章（图标 + 名称）
///
/// 用于在 skill 详情页等地方展示 Agent 标识
struct AgentBadgeView: View {

    let agentType: AgentType
    var isActive: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: agentType.iconName)
                .font(.caption2)
            Text(agentType.displayName)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Constants.AgentColors.color(for: agentType)
                .opacity(isActive ? 0.15 : 0.05)
        )
        .foregroundStyle(
            isActive
                ? Constants.AgentColors.color(for: agentType)
                : .secondary
        )
        .cornerRadius(4)
    }
}
