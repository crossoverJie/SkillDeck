import SwiftUI

/// RepositoryBrowserView displays skills available in a user-configured custom repository.
///
/// Occupies the "content" (middle) column of NavigationSplitView when a custom repo
/// is selected in the sidebar. The layout and patterns mirror RegistryBrowserView.
///
/// Data source: the locally cloned Git repository at `~/.agents/repos/<slug>/`.
/// Skills are discovered by scanning for SKILL.md files — no network requests needed
/// for browsing. A network request (git pull via SSH) only happens on explicit sync.
struct RepositoryBrowserView: View {

    /// ViewModel for this specific repository
    /// @Bindable enables two-way bindings ($viewModel.property) for @Observable classes
    @Bindable var viewModel: RepositoryBrowserViewModel

    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        VStack(spacing: 0) {
            // Repo info header: platform icon + SSH URL + sync status
            repoHeader
            Divider()

            // Main content area
            if viewModel.isLoading && viewModel.allSkills.isEmpty {
                loadingView
            } else if let errorMessage = viewModel.errorMessage, viewModel.allSkills.isEmpty {
                errorView(message: errorMessage)
            } else if viewModel.displayedSkills.isEmpty && !trimmedSearchText.isEmpty {
                // Search is active but no skills match the query
                emptyState
            } else if viewModel.allSkills.isEmpty {
                // Repo is cloned but contains no SKILL.md files (or scan hasn't returned yet)
                noSkillsState
            } else {
                skillList
            }
        }
        // Dynamic navigation title: shows the repo's display name
        .navigationTitle(viewModel.repository.name)
        // Native macOS search bar — filters skill list locally (no network call)
        .searchable(text: $viewModel.searchText, prompt: "Filter skills…")
        // Toolbar: Sync button
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await viewModel.sync() }
                } label: {
                    if viewModel.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .help("Sync repository (git pull)")
                .disabled(viewModel.isSyncing)
            }
        }
        // Load skills when the view first appears
        .task {
            await viewModel.onAppear()
        }
        // Re-load after sync completes (when repoSyncStatuses changes for this repo)
        .onChange(of: skillManager.repoSyncStatuses[viewModel.repository.id]) { _, newStatus in
            if case .success = newStatus {
                Task { await viewModel.loadSkills() }
            }
        }
        // Install sheet: same .sheet(item:) pattern as RegistryBrowserView
        .sheet(item: $viewModel.installVM, onDismiss: {
            viewModel.installVM?.cleanup()
            viewModel.installVM = nil
        }) { vm in
            SkillInstallView(viewModel: vm)
                .environment(skillManager)
        }
    }

    // MARK: - Sub-views

    /// Header showing repository metadata and last sync time
    private var repoHeader: some View {
        HStack(spacing: 8) {
            // Platform icon
            Image(systemName: viewModel.repository.platform.iconName)
                .foregroundStyle(.secondary)

            // Repository URL (truncated in the middle to fit)
            Text(viewModel.repository.repoURL)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if viewModel.isSyncing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Syncing...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Sync Now") {
                    Task { await viewModel.sync() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Last synced timestamp
            if let date = viewModel.repository.lastSyncedAt {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text("Synced \(gitStyleRelativeTime(from: date, now: context.date))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .help(absoluteDateText(date))
            } else {
                Text("Never synced")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Loading spinner for initial load
    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Scanning repository…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Error state view (e.g., "not yet synced")
    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 280)

            // Offer to sync immediately
            Button("Sync Now") {
                Task { await viewModel.sync() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(viewModel.isSyncing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// State when the repository is cloned but contains no SKILL.md files
    private var noSkillsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No Skills Found")
                .font(.headline)
            Text("This repository contains no SKILL.md files.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Empty state when search returns no results
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No skills match \"\(trimmedSearchText)\"")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var trimmedSearchText: String {
        viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Compact relative time style similar to git UIs (e.g. "3m ago", "2h ago", "yesterday").
    private func gitStyleRelativeTime(from date: Date, now: Date) -> String {
        let delta = now.timeIntervalSince(date)
        if delta < 0 {
            return "just now"
        }
        if delta < 60 {
            return "just now"
        }
        if delta < 3600 {
            return "\(Int(delta / 60))m ago"
        }
        if delta < 86_400 {
            return "\(Int(delta / 3600))h ago"
        }
        if delta < 172_800 {
            return "yesterday"
        }
        if delta < 604_800 {
            return "\(Int(delta / 86_400))d ago"
        }
        if delta < 2_592_000 {
            return "\(Int(delta / 604_800))w ago"
        }
        if delta < 31_536_000 {
            return "\(Int(delta / 2_592_000))mo ago"
        }
        return "\(Int(delta / 31_536_000))y ago"
    }

    /// Full timestamp shown on hover so users can inspect exact sync time.
    private func absoluteDateText(_ date: Date) -> String {
        Self.absoluteDateFormatter.string(from: date)
    }

    private static let absoluteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Scrollable list of skills
    private var skillList: some View {
        List(selection: $viewModel.selectedSkillID) {
            ForEach(viewModel.displayedSkills) { skill in
                // Each row is a button that selects the skill for the detail pane
                RepositorySkillRowView(
                    skill: skill,
                    isInstalled: viewModel.isInstalled(skill),
                    isInstallEnabled: viewModel.canInstallFromLocal,
                    installDisabledReason: viewModel.installDisabledReason,
                    onInstall: { viewModel.installSkill(skill) }
                )
                // .tag associates this row with the skill ID for List selection tracking
                .tag(skill.id)
                .listRowSeparator(.visible)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Repository Skill Row

/// Displays a single skill from a custom repository.
///
/// Shows: skill name, description, tags, installed badge, and Install button.
/// The layout is consistent with RegistrySkillRowView.
private struct RepositorySkillRowView: View {

    let skill: GitService.DiscoveredSkill
    let isInstalled: Bool
    let isInstallEnabled: Bool
    let installDisabledReason: String?
    let onInstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Skill info (left side)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Skill display name (fallback to directory id if metadata name is empty)
                    Text(skill.metadata.name.isEmpty ? skill.id : skill.metadata.name)
                        .font(.headline)
                        .lineLimit(1)

                    // "Installed" badge — same green capsule style as RegistrySkillRowView
                    if isInstalled {
                        Text("Installed")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }

                // Description (secondary text)
                if !skill.metadata.description.isEmpty {
                    Text(skill.metadata.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

            }

            Spacer()

            // Install button
            Button("Install") {
                onInstall()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isInstalled || !isInstallEnabled)
            .help(installHelpText)
        }
        .padding(.vertical, 4)
    }

    private var installHelpText: String {
        if isInstalled { return "Already installed" }
        if let installDisabledReason { return installDisabledReason }
        return "Install this skill from local repository clone"
    }
}
