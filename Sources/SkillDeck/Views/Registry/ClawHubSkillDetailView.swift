import SwiftUI
import AppKit

/// ClawHubSkillDetailView shows marketplace metadata plus the full rendered SKILL.md content.
///
/// It follows the same three-pane pattern as the existing registry detail view, but the fields and
/// actions are ClawHub-specific and installation always targets OpenClaw for this first release.
struct ClawHubSkillDetailView: View {
    let skill: ClawHubSkill
    let isInstalled: Bool
    let isInstalling: Bool
    let onInstall: () -> Void
    let viewModel: ClawHubBrowserViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                Divider()
                packageInfoSection
                if let content = viewModel.fetchedContent {
                    skillMetadataSection(content.metadata)
                }
                Divider()
                actionsSection
                Divider()
                skillContentSection
            }
            .padding()
        }
        .navigationTitle(skill.name)
        .task(id: skill.id) {
            await viewModel.loadSelection(for: skill)
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(skill.name)
                    .font(.title)
                    .bold()
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
                Text("Slug:")
                    .foregroundStyle(.secondary)
                Text(skill.slug)
                    .textSelection(.enabled)
            }
            .font(.subheadline)

            Text(skill.descriptionText)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var packageInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Package Info")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Marketplace").foregroundStyle(.secondary)
                    Text("ClawHub")
                }
                GridRow {
                    Text("Downloads").foregroundStyle(.secondary)
                    Text(skill.formattedDownloads)
                }
                GridRow {
                    Text("Stars").foregroundStyle(.secondary)
                    Text(skill.formattedStars)
                }
                if let version = viewModel.selectedSkillDetail?.installVersion ?? skill.latestVersion {
                    GridRow {
                        Text("Latest Version").foregroundStyle(.secondary)
                        Text(version).textSelection(.enabled)
                    }
                }
                if let owner = ownerText {
                    GridRow {
                        Text("Owner").foregroundStyle(.secondary)
                        Text(owner).textSelection(.enabled)
                    }
                }
                if let updatedDate = skill.formattedUpdatedDate {
                    GridRow {
                        Text("Updated").foregroundStyle(.secondary)
                        Text(updatedDate)
                    }
                }
                if let publishedDate = viewModel.selectedSkillDetail?.formattedLatestVersionDate {
                    GridRow {
                        Text("Latest Publish Date").foregroundStyle(.secondary)
                        Text(publishedDate)
                    }
                }
                if let license = viewModel.selectedSkillDetail?.license {
                    GridRow {
                        Text("License").foregroundStyle(.secondary)
                        Text(license)
                    }
                }
                if let moderation = moderationText {
                    GridRow {
                        Text("Moderation").foregroundStyle(.secondary)
                        Text(moderation)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.subheadline)

            if let detailError = viewModel.detailError {
                Label(detailError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func skillMetadataSection(_ metadata: SkillMetadata) -> some View {
        let hasUsefulInfo = !metadata.description.isEmpty
            || metadata.author != nil
            || metadata.version != nil
            || metadata.license != nil

        if hasUsefulInfo {
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Skill Metadata")
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    if !metadata.description.isEmpty {
                        GridRow {
                            Text("Description").foregroundStyle(.secondary)
                            Text(metadata.description)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let author = metadata.author {
                        GridRow {
                            Text("Author").foregroundStyle(.secondary)
                            Text(author).textSelection(.enabled)
                        }
                    }
                    if let version = metadata.version {
                        GridRow {
                            Text("Version").foregroundStyle(.secondary)
                            Text(version).textSelection(.enabled)
                        }
                    }
                    if let license = metadata.license {
                        GridRow {
                            Text("License").foregroundStyle(.secondary)
                            Text(license).textSelection(.enabled)
                        }
                    }
                }
                .font(.subheadline)
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)

            HStack(spacing: 12) {
                Button {
                    onInstall()
                } label: {
                    if isInstalling {
                        Label {
                            Text("Installing...")
                        } icon: {
                            ProgressView()
                                .controlSize(.small)
                        }
                    } else {
                        Label("Install to OpenClaw", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInstalled || isInstalling)

                Button {
                    NSWorkspace.shared.open(skill.browserURL)
                } label: {
                    Label("View on ClawHub", systemImage: "safari")
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Install Target")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("OpenClaw (installed via SkillDeck canonical directory + symlink)")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(.rect(cornerRadius: 6))
            }
            .padding(.top, 4)
        }
    }

    private var skillContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skill Content")
                .font(.headline)

            if viewModel.isLoadingContent {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading SKILL.md from ClawHub...")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            } else if let error = viewModel.contentError {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(error)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }

                    Button {
                        NSWorkspace.shared.open(skill.browserURL)
                    } label: {
                        Label("View on ClawHub instead", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 8)
            } else if let content = viewModel.fetchedContent {
                if !content.markdownBody.isEmpty {
                    MarkdownContentView(markdownText: content.markdownBody)
                } else {
                    Text("No content available.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .italic()
                }
            }
        }
    }

    private var ownerText: String? {
        let handle = viewModel.selectedSkillDetail?.skill.ownerHandle ?? skill.ownerHandle
        let displayName = viewModel.selectedSkillDetail?.skill.ownerDisplayName ?? skill.ownerDisplayName

        switch (handle, displayName) {
        case let (handle?, displayName?) where !displayName.isEmpty && displayName.caseInsensitiveCompare(handle) != .orderedSame:
            return "@\(handle) (\(displayName))"
        case let (handle?, _):
            return "@\(handle)"
        case let (_, displayName?) where !displayName.isEmpty:
            return displayName
        default:
            return nil
        }
    }

    private var moderationText: String? {
        guard let detail = viewModel.selectedSkillDetail else { return nil }

        switch (detail.moderationVerdict, detail.moderationSummary) {
        case let (verdict?, summary?) where !summary.isEmpty:
            return "\(verdict): \(summary)"
        case let (verdict?, _):
            return verdict
        case let (_, summary?) where !summary.isEmpty:
            return summary
        default:
            return nil
        }
    }
}
