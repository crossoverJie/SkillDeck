import SwiftUI

/// ScopeBadge displays the skill's scope badge
///
/// Three scopes have different colors and icons:
/// - Global (blue): shared global skill
/// - Local (gray): Agent local skill
/// - Project (green): project-level skill
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
