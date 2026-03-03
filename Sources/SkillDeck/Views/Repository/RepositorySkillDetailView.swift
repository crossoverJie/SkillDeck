import SwiftUI

/// RepositorySkillDetailView renders detail content for a selected skill from a custom repository.
///
/// Shown in the right pane of NavigationSplitView when user selects a row in RepositoryBrowserView.
/// Content is fully local (from scanned SKILL.md), no additional network request is needed.
struct RepositorySkillDetailView: View {

    let skill: GitService.DiscoveredSkill
    let repository: SkillRepository
    let isInstalled: Bool
    let canInstall: Bool
    let installDisabledReason: String?
    let onInstall: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                Divider()

                metadataSection

                Divider()

                actionsSection

                Divider()

                markdownSection
            }
            .padding()
        }
        .navigationTitle(skill.metadata.name.isEmpty ? skill.id : skill.metadata.name)
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(skill.metadata.name.isEmpty ? skill.id : skill.metadata.name)
                    .font(.title)
                    .fontWeight(.bold)
                    .textSelection(.enabled)

                if isInstalled {
                    Text("Installed")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 4) {
                Text("ID:")
                    .foregroundStyle(.secondary)
                Text(skill.id)
                    .textSelection(.enabled)
            }
            .font(.subheadline)

            if !skill.metadata.description.isEmpty {
                Text(skill.metadata.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Repository").foregroundStyle(.secondary)
                    Text(repository.name).textSelection(.enabled)
                }
                GridRow {
                    Text("Path").foregroundStyle(.secondary)
                    Text(skill.skillMDPath)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                if let author = skill.metadata.author {
                    GridRow {
                        Text("Author").foregroundStyle(.secondary)
                        Text(author).textSelection(.enabled)
                    }
                }
                if let version = skill.metadata.version {
                    GridRow {
                        Text("Version").foregroundStyle(.secondary)
                        Text(version).textSelection(.enabled)
                    }
                }
                if let license = skill.metadata.license {
                    GridRow {
                        Text("License").foregroundStyle(.secondary)
                        Text(license).textSelection(.enabled)
                    }
                }
            }
            .font(.subheadline)
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.headline)

            Button {
                onInstall()
            } label: {
                Label("Install Skill", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isInstalled || !canInstall)
            .help(installHelpText)
        }
    }

    @ViewBuilder
    private var markdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Skill Content")
                .font(.headline)

            if skill.markdownBody.isEmpty {
                Text("No markdown content available in this SKILL.md.")
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                MarkdownContentView(markdownText: skill.markdownBody)
            }
        }
    }

    private var installHelpText: String {
        if isInstalled { return "Already installed" }
        if let installDisabledReason { return installDisabledReason }
        return "Install this skill from local repository clone"
    }
}
