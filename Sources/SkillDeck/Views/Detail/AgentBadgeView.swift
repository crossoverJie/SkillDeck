import SwiftUI

/// AgentBadgeView displays a small Agent badge (icon + name)
///
/// Used to show Agent identifier in skill detail page, etc.
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
