import SwiftUI

/// SkillRowView is the skill card for each row in the list
///
/// Displays skill name, description, scope badge, and a compact installed Agent summary.
struct SkillRowView: View {

    let skill: Skill
    /// Project rows carry their source project name so same-named skills remain distinguishable.
    let projectName: String?

    init(skill: Skill, projectName: String? = nil) {
        self.skill = skill
        self.projectName = projectName
    }

    /// Get SkillManager from environment for reading updateStatuses dictionary
    /// @Environment is SwiftUI's dependency injection mechanism (similar to Spring's @Autowired)
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // First row: name + badges
            HStack(spacing: 6) {
                Text(skill.displayName)
                    .appFont(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                ScopeBadge(scope: skill.scope)
                    .fixedSize()

                // F12: Display different indicator icons based on update check status
                updateStatusIndicator

                Spacer(minLength: 4)

                // The dashboard column is intentionally narrow. Showing every installed agent here
                // caused names and scope badges to wrap, so the row shows a stable three-icon preview.
                if !skill.installations.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(visibleInstallations) { installation in
                            Image(systemName: installation.agentType.iconName).appFont(.caption)
                                .foregroundStyle(Constants.AgentColors.color(for: installation.agentType))
                                // Reduce opacity for inherited installation icons to visually distinguish from direct installations
                                .opacity(installation.isTrulyInherited ? 0.4 : 1.0)
                                // Hover tooltip: inherited installation shows "Copilot CLI (via ~/.claude/skills)"
                                .help(installation.isTrulyInherited
                                    ? "\(installation.agentType.displayName) (via \(installation.parentDirectoryDisplayPath))"
                                    : installation.agentType.displayName)
                        }
                        if hiddenInstallationCount > 0 {
                            Text("+\(hiddenInstallationCount)")
                                .appFont(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .fixedSize()
                    .help(installationSummary)
                }
            }

            // Second row: description (max 2 lines)
            if !skill.metadata.description.isEmpty {
                Text(skill.metadata.description).appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Third row: author + version + source
            HStack(spacing: 12) {
                if let author = skill.metadata.author {
                    Label(author, systemImage: "person").appFont(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let version = skill.metadata.version {
                    Label("v\(version)", systemImage: "tag").appFont(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let lockEntry = skill.lockEntry {
                    Label(lockEntry.source, systemImage: "link").appFont(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let projectName {
                    Label(projectName, systemImage: "folder")
                        .appFont(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Update Status Indicator

    /// The list row previews a bounded number of agents; details still expose every installation.
    private var visibleInstallations: ArraySlice<SkillInstallation> {
        skill.installations.prefix(3)
    }

    private var hiddenInstallationCount: Int {
        max(skill.installations.count - visibleInstallations.count, 0)
    }

    /// Tooltip keeps the complete installation information available without expanding the row.
    private var installationSummary: String {
        skill.installations.map { installation in
            installation.isTrulyInherited
                ? "\(installation.agentType.displayName) (via \(installation.parentDirectoryDisplayPath))"
                : installation.agentType.displayName
        }.joined(separator: ", ")
    }

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
                .foregroundStyle(.orange).appFont(.caption)
                .help("Update available")
        case .upToDate:
            // Up to date: green checkmark in filled circle icon
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green).appFont(.caption)
                .help("Up to date")
        case .error(let message):
            // Check failed: yellow warning triangle icon, hover shows error details
            // .help() sets mouse hover tooltip (native macOS feature)
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow).appFont(.caption)
                .help("Check failed: \(message)")
        }
    }
}
