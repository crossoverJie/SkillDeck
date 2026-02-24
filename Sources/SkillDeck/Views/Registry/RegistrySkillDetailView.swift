import SwiftUI

/// RegistrySkillDetailView displays detailed information for a selected skills.sh registry skill
///
/// Shown in the right (detail) pane of NavigationSplitView when a registry skill is clicked.
/// In addition to basic metadata from the API (name, source, installs), this view now also:
/// - Fetches the full SKILL.md content from GitHub (via SkillContentFetcher)
/// - Shows parsed metadata (author, version, license) from the YAML frontmatter
/// - Renders the markdown body natively using MarkdownContentView
///
/// Content loading is triggered by `.task(id: skill.id)` — when the user clicks a different
/// skill, the previous fetch is automatically cancelled and a new one starts.
///
/// This follows the same pattern as SkillDetailView but adapted for remote RegistrySkill data.
struct RegistrySkillDetailView: View {

    /// The selected registry skill to display
    let skill: RegistrySkill

    /// Whether this skill is already installed locally
    let isInstalled: Bool

    /// Closure called when user clicks the "Install" button
    let onInstall: () -> Void

    /// Reference to the RegistryBrowserViewModel for content-loading state
    ///
    /// The ViewModel holds `fetchedContent`, `isLoadingContent`, and `contentError` properties
    /// that drive the content section's three states (loading / error / loaded).
    /// Passed from ContentView where the ViewModel is already available.
    let viewModel: RegistryBrowserViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header section: name + installed badge
                headerSection

                Divider()

                // Package info section: source, installs, etc.
                packageInfoSection

                // Skill metadata section: author, version, license from SKILL.md frontmatter
                // Only shown when content has been fetched and metadata contains useful info
                if let content = viewModel.fetchedContent {
                    skillMetadataSection(content.metadata)
                }

                Divider()

                // Actions section: install + open in browser
                actionsSection

                Divider()

                // Skill content section: rendered SKILL.md markdown body
                // Shows loading spinner, error fallback, or rendered content
                skillContentSection
            }
            .padding()
        }
        .navigationTitle(skill.name)
        // `.task(id:)` runs an async task when the view appears, AND re-runs it whenever `id` changes.
        // When `id` changes (user clicks a different skill), SwiftUI automatically cancels the
        // previous task and starts a new one. This prevents stale content from appearing.
        // Similar to React's useEffect with a dependency array: useEffect(() => { ... }, [skill.id])
        .task(id: skill.id) {
            await viewModel.loadSkillContent(for: skill)
        }
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

    /// Skill metadata section: author, version, license, description from SKILL.md YAML frontmatter
    ///
    /// Only shown when content has been fetched and the metadata contains at least one
    /// useful field beyond the name. Uses the same Grid layout as packageInfoSection
    /// for visual consistency.
    ///
    /// - Parameter metadata: The parsed SkillMetadata from SKILL.md frontmatter
    @ViewBuilder
    private func skillMetadataSection(_ metadata: SkillMetadata) -> some View {
        // Only show this section if metadata has at least one useful field
        // (description, author, version, or license)
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
                    // Description from YAML frontmatter (may differ from the registry listing)
                    if !metadata.description.isEmpty {
                        GridRow {
                            Text("Description").foregroundStyle(.secondary)
                            Text(metadata.description)
                                .textSelection(.enabled)
                                // fixedSize allows text to wrap to multiple lines
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    // Author from metadata.author nested field
                    if let author = metadata.author {
                        GridRow {
                            Text("Author").foregroundStyle(.secondary)
                            Text(author).textSelection(.enabled)
                        }
                    }
                    // Version from metadata.version nested field
                    if let version = metadata.version {
                        GridRow {
                            Text("Version").foregroundStyle(.secondary)
                            Text(version).textSelection(.enabled)
                        }
                    }
                    // License from top-level license field
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

    /// Skill content section: rendered SKILL.md markdown body
    ///
    /// Displays three states based on the ViewModel's content-loading properties:
    /// 1. **Loading**: ProgressView spinner while content is being fetched from GitHub
    /// 2. **Error**: Error message with a fallback "View on skills.sh" link
    /// 3. **Loaded**: Full SKILL.md body rendered as native SwiftUI views via MarkdownContentView
    ///
    /// This is similar to React's conditional rendering pattern:
    /// `isLoading ? <Spinner/> : error ? <Error/> : <Content/>`
    private var skillContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skill Content")
                .font(.headline)

            if viewModel.isLoadingContent {
                // State 1: Loading — show spinner with descriptive label
                HStack(spacing: 8) {
                    // ProgressView() creates an indeterminate spinner (macOS native style)
                    ProgressView()
                        // .controlSize(.small) makes the spinner compact, appropriate for inline use
                        .controlSize(.small)
                    Text("Loading SKILL.md from GitHub...")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            } else if let error = viewModel.contentError {
                // State 2: Error — show message with fallback link
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(error)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }

                    // Fallback: link to view the skill on skills.sh in a browser
                    Button {
                        let urlString = "https://skills.sh/\(skill.source)/\(skill.skillId)"
                        if let url = URL(string: urlString) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("View on skills.sh instead", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 8)
            } else if let content = viewModel.fetchedContent {
                // State 3: Loaded — render markdown body natively
                // MarkdownContentView parses the markdown string via swift-markdown's AST
                // and renders each block element (headings, paragraphs, code blocks, etc.)
                // as native SwiftUI views.
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
}
