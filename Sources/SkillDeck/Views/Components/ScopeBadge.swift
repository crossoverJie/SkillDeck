import SwiftUI

/// ScopeBadge 显示 skill 的作用域徽章
///
/// 三种作用域有不同的颜色和图标：
/// - Global（蓝色）：共享全局 skill
/// - Local（灰色）：Agent 本地 skill
/// - Project（绿色）：项目级 skill
struct ScopeBadge: View {

    let scope: SkillScope

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
                .font(.caption2)
            Text(scope.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Constants.ScopeColors.color(for: scope).opacity(0.12))
        .foregroundStyle(Constants.ScopeColors.color(for: scope))
        .cornerRadius(4)
    }

    private var iconName: String {
        switch scope {
        case .sharedGlobal: "globe"
        case .agentLocal: "person"
        case .project: "folder"
        }
    }
}
