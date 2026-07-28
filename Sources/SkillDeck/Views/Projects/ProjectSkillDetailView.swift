import AppKit
import SwiftUI

/// ProjectSkillDetailView presents a project-local skill and its independent Git update lifecycle.
/// Its state comes from ProjectSkillDetailViewModel so actions always stay within the selected project.
struct ProjectSkillDetailView: View {
    let row: ProjectSkillRow
    @State private var viewModel: ProjectSkillDetailViewModel

    init(row: ProjectSkillRow) {
        self.row = row
        _viewModel = State(initialValue: ProjectSkillDetailViewModel(row: row))
    }

    var body: some View {
        Group {
            if let skill = viewModel.skill {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(skill)
                        Divider()
                        repositorySection(skill)
                        Divider()
                        MarkdownContentView(markdownText: skill.markdownBody, showsChineseTranslation: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(8)
                    }
                    .padding()
                }
                .navigationTitle(skill.displayName)
                .toolbar { toolbar }
            } else if viewModel.isLoading {
                ProgressView()
            } else {
                ContentUnavailableView(
                    L10n.currentString(L10nKeys.projectDetailReadFailed),
                    systemImage: "exclamationmark.triangle",
                    description: Text(viewModel.errorMessage ?? row.sourceURL.path)
                )
            }
        }
        .task { await viewModel.load() }
    }

    private func header(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(skill.displayName).appFont(.title2).fontWeight(.bold)
                ScopeBadge(scope: skill.scope)
            }
            if !skill.metadata.description.isEmpty {
                Text(skill.metadata.description).appFont(.body).foregroundStyle(.secondary)
            }
            Text(skill.canonicalURL.tildeAbbreviatedPath)
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func repositorySection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.currentString(L10nKeys.projectDetailUpdate)).appFont(.headline)
            if let entry = skill.lockEntry {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text(L10n.currentString(L10nKeys.projectDetailSource)).foregroundStyle(.secondary)
                        Text(entry.source).textSelection(.enabled)
                    }
                    GridRow {
                        Text(L10n.currentString(L10nKeys.projectDetailRepository)).foregroundStyle(.secondary)
                        Text(entry.sourceUrl).textSelection(.enabled)
                    }
                    GridRow {
                        Text(L10n.currentString(L10nKeys.projectDetailUpdatedAt)).foregroundStyle(.secondary)
                        Text(entry.updatedAt.formattedDate)
                    }
                }
                .appFont(.subheadline)

                HStack(spacing: 8) {
                    if viewModel.isChecking || viewModel.isUpdating {
                        ProgressView().controlSize(.small)
                    }
                    if viewModel.hasUpdate {
                        Label(L10n.currentString(L10nKeys.projectDetailUpdateFound), systemImage: "arrow.up.circle.fill")
                            .foregroundStyle(.orange)
                        Button(L10n.currentString(L10nKeys.projectDetailUpdateNow)) { Task { await viewModel.update() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.isUpdating)
                    } else {
                        Button(L10n.currentString(L10nKeys.projectDetailCheckUpdate)) { Task { await viewModel.checkForUpdate() } }
                            .disabled(viewModel.isChecking)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    TextField("owner/repo", text: $viewModel.repositoryInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await viewModel.linkRepository() } }
                        .disabled(viewModel.isLinking)
                    Button(L10n.currentString(L10nKeys.projectDetailLinkRepository)) { Task { await viewModel.linkRepository() } }
                        .disabled(viewModel.repositoryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLinking)
                }
            }
            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .appFont(.caption)
                    .foregroundStyle(.orange)
            }
            if let statusMessage = viewModel.statusMessage {
                Label(statusMessage, systemImage: viewModel.hasUpdate ? "arrow.up.circle.fill" : "checkmark.circle.fill")
                    .appFont(.caption)
                    .foregroundStyle(viewModel.hasUpdate ? .orange : .green)
            }
        }
    }

    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: row.sourceURL.path)
            } label: {
                Image(systemName: "folder")
            }
            .help(L10n.currentString(L10nKeys.commonShowInFinder))

            Button { openInTerminal() } label: {
                Image(systemName: "terminal")
            }
            .help(L10n.currentString(L10nKeys.projectDetailOpenTerminal))

            Button {
                NSWorkspace.shared.open(row.sourceURL.appendingPathComponent("SKILL.md"))
            } label: {
                Image(systemName: "pencil")
            }
            .help(L10n.currentString(L10nKeys.projectDetailOpenEditor))
        }
    }

    /// A directory must be opened with a terminal app explicitly; NSWorkspace.open alone would show Finder.
    private func openInTerminal() {
        for bundleID in ["dev.warp.Warp-Stable", "dev.warp.Warp", "com.googlecode.iterm2", "com.apple.Terminal"] {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.open(
                    [row.sourceURL],
                    withApplicationAt: appURL,
                    configuration: NSWorkspace.OpenConfiguration()
                ) { _, _ in }
                return
            }
        }
    }
}
