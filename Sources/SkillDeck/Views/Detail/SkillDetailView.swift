import SwiftUI

/// SkillDetailView is the skill detail page (F03)
///
/// Displays complete skill information, including:
/// - Basic info (name, description, author, version)
/// - Agent assignment status (toggleable)
/// - Markdown body
/// - Lock file info
/// - Action buttons (edit, delete, open in Finder/Terminal)
struct SkillDetailView: View {

    let skillID: String
    @Bindable var viewModel: SkillDetailViewModel
    @Environment(SkillManager.self) private var skillManager

    /// Editor ViewModel (created only during editing)
    @State private var editorVM: SkillEditorViewModel?

    /// Copy path button feedback state: shows green checkmark when true, auto-resets after 1.5 seconds
    @State private var pathCopied = false

    var body: some View {
        // SwiftUI version of guard-let: show empty state if skill doesn't exist
        if let skill = viewModel.skill(id: skillID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header info
                    headerSection(skill)

                    // Package Info (with update status) - placed first, visible when entering detail page
                    // Show full package info when lockEntry exists; otherwise show manual repo linking UI
                    Divider()
                    if let lockEntry = skill.lockEntry {
                        lockFileSection(skill, lockEntry)
                    } else {
                        linkToRepoSection(skill)
                    }

                    Divider()

                    // Agent assignment section
                    agentAssignmentSection(skill)

                    Divider()

                    // Markdown body
                    markdownSection(skill)
                }
                .padding()
            }
            .navigationTitle(skill.displayName)
            .toolbar {
                ToolbarItemGroup {
                    // Reveal in Finder
                    Button {
                        viewModel.revealInFinder(skill: skill)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Reveal in Finder")

                    // Open in Terminal
                    Button {
                        viewModel.openInTerminal(skill: skill)
                    } label: {
                        Image(systemName: "terminal")
                    }
                    .help("Open in Terminal")

                    // Edit button
                    Button {
                        let vm = SkillEditorViewModel(skillManager: skillManager)
                        vm.load(skill: skill)
                        editorVM = vm
                        viewModel.isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .help("Edit SKILL.md")
                }
            }
            // sheet is macOS modal dialog (slides in from top)
            .sheet(isPresented: $viewModel.isEditing) {
                if let editorVM {
                    SkillEditorView(
                        viewModel: editorVM,
                        isPresented: $viewModel.isEditing
                    )
                    .frame(minWidth: 700, minHeight: 500)
                }
            }
        } else {
            EmptyStateView(
                icon: "questionmark.circle",
                title: "Skill Not Found",
                subtitle: "The selected skill may have been deleted"
            )
        }
    }

    // MARK: - Sections

    /// Header info section
    @ViewBuilder
    private func headerSection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(skill.displayName)
                    .font(.title)
                    .fontWeight(.bold)

                ScopeBadge(scope: skill.scope)
            }

            if !skill.metadata.description.isEmpty {
                Text(skill.metadata.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            // Metadata row
            HStack(spacing: 16) {
                if let author = skill.metadata.author {
                    Label(author, systemImage: "person")
                }
                if let version = skill.metadata.version {
                    Label("v\(version)", systemImage: "tag")
                }
                if let license = skill.metadata.license {
                    Label(license, systemImage: "doc.text")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            // Path display + copy button
            HStack(spacing: 4) {
                Text(skill.canonicalURL.tildeAbbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)

                // Copy path button
                // NSPasteboard is macOS clipboard API, equivalent to iOS UIPasteboard
                // .generalPasteboard gets the system general clipboard (source of user's Cmd+V paste)
                Button {
                    let pasteboard = NSPasteboard.general
                    // clearContents() must be called before setString to clear old content
                    pasteboard.clearContents()
                    // Write full path (expanding ~ to absolute path for terminal use)
                    pasteboard.setString(skill.canonicalURL.path, forType: .string)

                    // Set copy success state, icon temporarily changes to green checkmark
                    pathCopied = true
                    // Task.sleep is non-blocking delay in Swift concurrency (like Python's asyncio.sleep)
                    // Auto-restore original icon after 1.5 seconds
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        pathCopied = false
                    }
                } label: {
                    // contentTransition(.symbolEffect(.replace)) makes SF Symbol icon
                    // use system built-in replacement animation (fade + scale) when switching, more natural than manual animation
                    // Swift's ternary requires both sides to have same type; .green is Color, .tertiary is
                    // HierarchicalShapeStyle, cannot mix directly. Use AnyShapeStyle type erasure to unify types.
                    Image(systemName: pathCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(pathCopied ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                        .contentTransition(.symbolEffect(.replace))
                }
                // .plain button style removes default border and background, looks like an icon
                .buttonStyle(.plain)
                .help("Copy path to clipboard")
                // animation modifier listens to pathCopied changes, automatically applies smooth transition to colors and other properties
                .animation(.easeInOut(duration: 0.2), value: pathCopied)
            }
        }
    }

    /// Agent assignment section (F06)
    @ViewBuilder
    private func agentAssignmentSection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent Assignment")
                .font(.headline)

            AgentToggleView(skill: skill, viewModel: viewModel)
        }
    }

    /// Markdown body section
    @ViewBuilder
    private func markdownSection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Documentation")
                .font(.headline)

            if skill.markdownBody.isEmpty {
                Text("No documentation available")
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                // Display markdown source in monospace font
                // Can be replaced with rendered markdown in the future
                Text(skill.markdownBody)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
            }
        }
    }

    /// Manual repository linking section — displayed when skill has no lockEntry
    ///
    /// Allows user to input GitHub repository address ("owner/repo" or full URL),
    /// after linking SkillDeck can check for updates. Link info stored in private cache, does not modify lock file.
    @ViewBuilder
    private func linkToRepoSection(_ skill: Skill) -> some View {
        // Read all @Observable properties into local variables to avoid
        // multiple accesses of @Observable properties causing AttributeGraph dependency cycles in deep ViewBuilder nesting.
        // SwiftUI's AttributeGraph creates dependency edges for each property access,
        // local variables only trigger dependency tracking once, reducing the probability of cycles.
        let isLinking = viewModel.isLinking
        let linkError = viewModel.linkError
        let inputIsEmpty = viewModel.repoURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        VStack(alignment: .leading, spacing: 8) {
            Text("Package Info")
                .font(.headline)

            Text("This skill is not linked to a repository. Link it to enable update checking.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Input row: TextField + Link button
            HStack(spacing: 8) {
                // $viewModel.repoURLInput two-way binding for input content
                // @Bindable property wrapper allows @Observable object properties to support $ syntax binding
                TextField("owner/repo", text: $viewModel.repoURLInput)
                    .textFieldStyle(.roundedBorder)
                    // .onSubmit triggers when user presses return (similar to HTML input's onKeyDown Enter)
                    .onSubmit {
                        Task { await viewModel.linkToRepository(skill: skill) }
                    }
                    .disabled(isLinking)

                if isLinking {
                    // Linking: show ProgressView (spinning indicator)
                    ProgressView()
                        .controlSize(.small)
                    Text("Linking...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Link") {
                        Task { await viewModel.linkToRepository(skill: skill) }
                    }
                    .disabled(inputIsEmpty)
                }
            }

            // Error message
            if let error = linkError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Lock file info section
    @ViewBuilder
    private func lockFileSection(_ skill: Skill, _ lockEntry: LockEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题行：Package Info + 更新检查按钮
            HStack {
                Text("Package Info")
                    .font(.headline)

                Spacer()

                // F12: 更新状态指示和操作按钮
                updateStatusView(skill)
            }

            // Grid is macOS 14+ grid layout (similar to HTML CSS Grid)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Source").foregroundStyle(.secondary)
                    Text(lockEntry.source).textSelection(.enabled)
                }
                GridRow {
                    Text("Repository").foregroundStyle(.secondary)
                    // If sourceUrl is valid URL, show as clickable link, opens in system default browser when clicked
                    if let url = URL(string: lockEntry.sourceUrl),
                       url.scheme != nil {
                        Link(lockEntry.sourceUrl, destination: url)
                            .textSelection(.enabled)
                    } else {
                        Text(lockEntry.sourceUrl).textSelection(.enabled)
                    }
                }
                // Prefer displaying commit hash (can be viewed directly on GitHub),
                // fallback to tree hash if not present (old skill not backfilled)
                GridRow {
                    if let commitHash = skill.localCommitHash {
                        Text("Commit").foregroundStyle(.secondary)
                        Text(commitHash)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("Tree Hash").foregroundStyle(.secondary)
                        Text(lockEntry.skillFolderHash)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                GridRow {
                    Text("Installed").foregroundStyle(.secondary)
                    Text(lockEntry.installedAt.formattedDate)
                }
                GridRow {
                    Text("Updated").foregroundStyle(.secondary)
                    Text(lockEntry.updatedAt.formattedDate)
                }
            }
            .font(.subheadline)
        }
    }

    /// F12: Update status indicator view
    ///
    /// Displays different UI based on viewModel's update check status:
    /// - Checking: ProgressView + "Checking..."
    /// - Has update: orange label + "Update" button
    /// - Updating: ProgressView + "Updating..."
    /// - Up to date: green checkmark (auto-disappears after 2 seconds)
    /// - Default: check button
    @ViewBuilder
    private func updateStatusView(_ skill: Skill) -> some View {
        if viewModel.isCheckingUpdate {
            // Checking for updates
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.isUpdating {
            // Performing update
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Updating...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if skill.hasUpdate {
            // Has available update: show hash comparison + GitHub link + Update button
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Label("Update Available", systemImage: "arrow.up.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Button("Update") {
                        Task { await viewModel.updateSkill(skill) }
                    }
                    .controlSize(.small)
                }

                // Commit hash comparison row + GitHub link
                // Displays localHash → remoteHash (7-character short format, consistent with git log --oneline)
                updateDetailRow(skill)
            }
        } else if viewModel.showUpToDate {
            // Already up to date (auto-disappears after 2 seconds)
            Label("Up to Date", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if let error = viewModel.updateError {
            // 更新检查出错
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            // Default state: show check button
            Button {
                Task { await viewModel.checkForUpdate(skill: skill) }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .controlSize(.small)
            .help("Check for updates")
        }
    }

    /// F12: Update detail row — displays commit hash comparison and GitHub link
    ///
    /// Layout: `abc1234 → def5678   View changes on GitHub ↗`
    /// - Hash comparison: local commit hash → remote commit hash (7-character short format, consistent with git log --oneline)
    /// - GitHub link: opens compare page in browser when clicked
    @ViewBuilder
    private func updateDetailRow(_ skill: Skill) -> some View {
        HStack(spacing: 6) {
            // Take first 7 characters short format (consistent with git log --oneline)
            // prefix(_:) returns Substring, needs to be wrapped in String()
            let localShort = skill.localCommitHash.map { String($0.prefix(7)) }
            let remoteShort = skill.remoteCommitHash.map { String($0.prefix(7)) }

            if let localShort, let remoteShort {
                // Have both commit hashes: show comparison `abc1234 → def5678`
                Text("\(localShort) → \(remoteShort)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else if let remoteShort {
                // Only have remote commit hash (fallback when old skill backfill failed)
                Text("→ \(remoteShort)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // GitHub compare link button
            if let url = githubCompareURL(skill) {
                // Use link-style text button, opens in browser when clicked
                // NSWorkspace.shared.open() is the standard way to open URLs on macOS
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: 2) {
                        Text("View changes on GitHub")
                        // arrow.up.right is external link icon (↗), indicates will jump to browser
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.caption2)
                }
                .buttonStyle(.link)
            }
        }
    }

    // MARK: - Helper Methods

    /// Generate GitHub compare URL
    ///
    /// Generates GitHub comparison page URL based on lockEntry.sourceUrl and commit hash:
    /// - Have both commit hashes: `https://github.com/owner/repo/compare/<local>...<remote>`
    ///   GitHub compare view shows all file differences between two commits
    /// - Only have remote commit hash: `https://github.com/owner/repo/commit/<remote>`
    ///   Shows detail page for the remote latest commit
    private func githubCompareURL(_ skill: Skill) -> URL? {
        guard let sourceUrl = skill.lockEntry?.sourceUrl,
              let baseURL = GitService.githubWebURL(from: sourceUrl),
              let remoteHash = skill.remoteCommitHash else {
            return nil
        }

        // If have local commit hash, generate compare URL to show differences between two commits
        // GitHub compare URL format: compare/<base>...<head>
        // Where `...` indicates three-dot diff (shows changes in head relative to base)
        if let localHash = skill.localCommitHash {
            return URL(string: "\(baseURL)/compare/\(localHash)...\(remoteHash)")
        }

        // No local commit hash (backfill not successful), only link to remote commit page
        return URL(string: "\(baseURL)/commit/\(remoteHash)")
    }
}
