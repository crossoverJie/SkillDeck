import SwiftUI

/// RegistrySkillDetailView displays detailed information for a selected skills.sh registry skill
///
/// Shown in the right (detail) pane of NavigationSplitView when a registry skill is clicked.
/// Since registry skills only have basic metadata from the API (name, source, installs),
/// this view is simpler than the local SkillDetailView — it focuses on:
/// - Skill name and source repository info
/// - Install count with formatted display
/// - Link to the skill's page on skills.sh
/// - Install button (reuses the existing F10 install flow)
///
/// This follows the same pattern as SkillDetailView but adapted for remote RegistrySkill data.
struct RegistrySkillDetailView: View {

    /// The selected registry skill to display
    let skill: RegistrySkill

    /// Whether this skill is already installed locally
    let isInstalled: Bool

    /// Closure called when user clicks the "Install" button
    let onInstall: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header section: name + installed badge
                headerSection

                Divider()

                // Package info section: source, installs, etc.
                packageInfoSection

                Divider()

                // Actions section: install + open in browser
                actionsSection
            }
            .padding()
        }
        .navigationTitle(skill.name)
    }

    // MARK: - Sections

    /// Header section: skill name and installed badge
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(skill.name)
                    .font(.title)
                    .fontWeight(.bold)
                    // .textSelection(.enabled) allows the user to select and copy text
                    .textSelection(.enabled)

                // "Installed" badge — same visual style as SkillInstallView and RegistrySkillRowView
                if isInstalled {
                    Text("Installed")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        // clipShape(Capsule()) creates a pill-shaped rounded rectangle
                        .clipShape(Capsule())
                }
            }

            // Skill ID (useful for CLI install commands)
            HStack(spacing: 4) {
                Text("ID:")
                    .foregroundStyle(.secondary)
                Text(skill.skillId)
                    .textSelection(.enabled)
            }
            .font(.subheadline)
        }
    }

    /// Package info section: source repo, install count, daily change
    ///
    /// Uses Grid layout (macOS 14+) for aligned label-value pairs,
    /// consistent with SkillDetailView's lock file info section.
    /// Grid is similar to HTML's CSS Grid — it aligns columns automatically.
    private var packageInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Package Info")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Source").foregroundStyle(.secondary)
                    Text(skill.source).textSelection(.enabled)
                }
                GridRow {
                    Text("Repository").foregroundStyle(.secondary)
                    // Show source as a clickable link to the GitHub repository
                    // Link is SwiftUI's built-in component for opening URLs in the default browser
                    if let url = URL(string: skill.repoURL) {
                        Link(skill.repoURL, destination: url)
                            .textSelection(.enabled)
                    } else {
                        Text(skill.repoURL).textSelection(.enabled)
                    }
                }
                GridRow {
                    Text("Installs").foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        // Show both formatted and exact count
                        Text(skill.formattedInstalls)
                            .fontWeight(.medium)
                        Text("(\(skill.installs))")
                            .foregroundStyle(.tertiary)
                    }
                }
                // Show daily change if available (from trending/hot data)
                if let change = skill.change, change != 0 {
                    GridRow {
                        Text("Daily Change").foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.green)
                            Text("+\(change)")
                                .foregroundStyle(.green)
                        }
                    }
                }
                // Show yesterday's installs if available (from trending data)
                if let yesterday = skill.installsYesterday {
                    GridRow {
                        Text("Yesterday").foregroundStyle(.secondary)
                        Text("\(yesterday) installs")
                    }
                }
            }
            .font(.subheadline)
        }
    }

    /// Actions section: install button + open on skills.sh
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)

            HStack(spacing: 12) {
                // Install button — triggers the install flow via the parent's onInstall callback
                Button {
                    onInstall()
                } label: {
                    Label("Install Skill", systemImage: "arrow.down.circle")
                }
                // .borderedProminent gives the button a filled, prominent appearance
                // This is the macOS equivalent of a "primary" button
                .buttonStyle(.borderedProminent)
                .disabled(isInstalled)

                // Open on skills.sh — opens the skill's detail page in the browser
                // URL format: https://skills.sh/{source}/{skillId}
                Button {
                    let urlString = "https://skills.sh/\(skill.source)/\(skill.skillId)"
                    if let url = URL(string: urlString) {
                        // NSWorkspace.shared.open() opens the URL in the default browser
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("View on skills.sh", systemImage: "safari")
                }
                .buttonStyle(.bordered)
            }

            // CLI install hint — shows the npx command for reference
            VStack(alignment: .leading, spacing: 4) {
                Text("CLI Install Command")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Monospaced font for code-like display
                Text("npx skills add \(skill.source)")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Use system text background color for code block appearance
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
            }
            .padding(.top, 4)
        }
    }
}
