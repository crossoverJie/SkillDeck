import SwiftUI

/// SkillRowView is the skill card for each row in the list
///
/// Displays skill name, description, scope badge, and installed Agent icons
struct SkillRowView: View {

    let skill: Skill

    /// Get SkillManager from environment for reading updateStatuses dictionary
    /// @Environment is SwiftUI's dependency injection mechanism (similar to Spring's @Autowired)
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // First row: name + badges
            HStack {
                Text(skill.displayName)
                    .font(.headline)

                ScopeBadge(scope: skill.scope)

                // F12: Display different indicator icons based on update check status
                updateStatusIndicator

                Spacer()

                // Installed Agent icon row
                // Use installations instead of installedAgents to get isInherited information
                // Inherited installation icons have reduced opacity, hover tooltip shows source
                HStack(spacing: 4) {
                    ForEach(skill.installations) { installation in
                        Image(systemName: installation.agentType.iconName)
                            .font(.caption)
                            .foregroundStyle(Constants.AgentColors.color(for: installation.agentType))
                            // Reduce opacity for inherited installation icons to visually distinguish from direct installations
                            .opacity(installation.isInherited ? 0.4 : 1.0)
                            // Hover tooltip: inherited installation shows "Copilot CLI (via ~/.claude/skills)"
                            .help(installation.isInherited && installation.inheritedFrom != nil
                                ? "\(installation.agentType.displayName) (via \(installation.inheritedFrom!.skillsDirectoryPath))"
                                : installation.agentType.displayName)
                    }
                }
            }

            // Second row: description (max 2 lines)
            if !skill.metadata.description.isEmpty {
                Text(skill.metadata.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Third row: author + version + source
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

    // MARK: - Update Status Indicator

    /// Renders different status indicators based on SkillUpdateStatus enum
    ///
    /// @ViewBuilder allows using conditional branches in computed properties to return different View types,
    /// the compiler automatically wraps them into concrete types of `some View` (similar to Java generics type erasure but resolved at compile time).
    /// Uses `switch` to exhaustively enumerate all enum cases (Swift enforces exhaustive matching, similar to Rust's match).
    @ViewBuilder
    private var updateStatusIndicator: some View {
        switch skillManager.updateStatuses[skill.id] ?? .notChecked {
        case .notChecked:
            // Default state: display nothing
            // EmptyView() is SwiftUI's empty view placeholder, takes no space
            EmptyView()
        case .checking:
            // Checking: display spinning progress indicator (ProgressView)
            // .controlSize(.mini) makes spinner smaller, suitable for inline display
            ProgressView()
                .controlSize(.mini)
        case .hasUpdate:
            // Update available: orange up arrow in filled circle icon
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .help("Update available")
        case .upToDate:
            // Up to date: green checkmark in filled circle icon
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
                .help("Up to date")
        case .error(let message):
            // Check failed: yellow warning triangle icon, hover shows error details
            // .help() sets mouse hover tooltip (native macOS feature)
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
                .help("Check failed: \(message)")
        }
    }
}
