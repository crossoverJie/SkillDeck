import SwiftUI

/// SkillInstallView is the F10 (one-click install) dialog interface
///
/// Two-step process:
/// 1. Enter GitHub repository URL → click "Scan" to scan
/// 2. Select skills to install and target Agent → click "Install" to install
///
/// Uses `.sheet()` to popup from SidebarView, automatically cleans up temp directory on close
struct SkillInstallView: View {

    /// ViewModel manages installation process state
    /// @Bindable allows @Observable object properties to create Binding (two-way binding)
    @Bindable var viewModel: SkillInstallViewModel

    /// Get dismiss action from environment, used to close sheet
    /// @Environment(\.dismiss) is SwiftUI's standard way to close currently presented view (sheet/popover, etc.)
    /// Replaces previous @Binding var isPresented, more decoupled — child view doesn't need to know how parent controls display
    @Environment(\.dismiss) private var dismiss

    /// Get SkillManager from environment (for checking detected Agents)
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar

            Divider()

            // Display different content based on current phase
            // Swift's switch is an expression, can be used directly in ViewBuilder
            switch viewModel.phase {
            case .inputURL:
                inputURLPhase
            case .fetching:
                fetchingPhase
            case .selectSkills:
                selectSkillsPhase
            case .installing:
                installingPhase
            case .completed:
                completedPhase
            case .error(let message):
                errorPhase(message)
            }
        }
        // Sheet modal minimum size (macOS standard practice)
        .frame(minWidth: 550, minHeight: 400)
    }

    // MARK: - Header

    /// Header bar (common to all phases)
    private var headerBar: some View {
        HStack {
            Text("Install Skills from GitHub")
                .font(.headline)
            Spacer()
            // Close button
            Button {
                // dismiss() closes current sheet, provided by SwiftUI environment
                // Parent view's .sheet(item:) onDismiss callback will automatically trigger cleanup
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Phase Views

    /// Phase 1: Input URL
    private var inputURLPhase: some View {
        VStack(spacing: 16) {
            Spacer()

            // Icon and description
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Enter a GitHub repository to scan for skills")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // URL input field
            // TextField is similar to HTML's <input type="text">, placeholder is gray hint text
            HStack {
                TextField("owner/repo or GitHub URL", text: $viewModel.repoURLInput)
                    .textFieldStyle(.roundedBorder)
                    // onSubmit listens for return key event (similar to HTML form submit)
                    .onSubmit {
                        guard !viewModel.repoURLInput.isEmpty else { return }
                        Task { await viewModel.fetchRepository() }
                    }

                Button("Scan") {
                    Task { await viewModel.fetchRepository() }
                }
                .disabled(viewModel.repoURLInput.trimmingCharacters(in: .whitespaces).isEmpty)
                // .keyboardShortcut(.return) makes button respond to return key
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 40)

            // History list: only shown when repoHistory is not empty
            // Users can click a history item to auto-fill the URL and trigger Scan
            if !viewModel.repoHistory.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Repositories")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 40)

                    // ScrollView wraps the history list to prevent too many entries from stretching the view
                    // .frame(maxHeight: 150) caps the height; content scrolls if it overflows
                    ScrollView {
                        VStack(spacing: 0) {
                            // ForEach requires Identifiable or an explicit id parameter
                            // Here we use source as the unique identifier (already deduplicated)
                            ForEach(viewModel.repoHistory, id: \.source) { entry in
                                Button {
                                    // Click a history item: auto-fill URL and trigger Scan
                                    Task {
                                        await viewModel.selectHistoryRepo(
                                            source: entry.source,
                                            sourceUrl: entry.sourceUrl
                                        )
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        // Clock arrow icon representing "history"
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                        Text(entry.source)
                                            .font(.callout)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    // contentShape expands the tappable area to the full row (by default only text is tappable)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                // Divider between rows (skip the last row)
                                if entry.source != viewModel.repoHistory.last?.source {
                                    Divider()
                                        .padding(.leading, 32)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(maxHeight: 150)
                    .padding(.horizontal, 36)
                }
            }

            Spacer()
        }
        .padding()
        // .task runs async code when the view first appears (like Android onResume + coroutine)
        // Used here to load repo history
        .task {
            await viewModel.loadHistory()
        }
    }

    /// Phase: Cloning and scanning in progress
    private var fetchingPhase: some View {
        VStack(spacing: 16) {
            Spacer()
            // ProgressView is macOS native loading indicator (spinning spinner)
            ProgressView()
                .controlSize(.large)
            Text(viewModel.progressMessage)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    /// Phase 2: Select skills and Agent
    private var selectSkillsPhase: some View {
        VStack(spacing: 0) {
            // Skill list (scrollable)
            // List is macOS native list component, with built-in selection, scrolling, etc.
            List {
                Section("Skills Found (\(viewModel.discoveredSkills.count))") {
                    ForEach(viewModel.discoveredSkills) { skill in
                        skillRow(skill)
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            // Agent selection area + install button
            VStack(spacing: 12) {
                // Agent selection area (two-row layout to avoid horizontal squeezing)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Install to:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // LazyVGrid adapts column width, automatically wraps based on available space
                    // adaptive(minimum: 120) means each column is at least 120pt, extra space is automatically distributed
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 8) {
                        // ForEach iterates through all detected Agents
                        ForEach(AgentType.allCases) { agentType in
                            let isDetected = skillManager.agents.first { $0.type == agentType }?.isInstalled == true
                            // Toggle is macOS switch/checkbox component
                            Toggle(isOn: Binding(
                                get: { viewModel.selectedAgents.contains(agentType) },
                                set: { _ in viewModel.toggleAgentSelection(agentType) }
                            )) {
                                Label(agentType.displayName, systemImage: agentType.iconName)
                                    .font(.caption)
                            }
                            .toggleStyle(.checkbox)
                            // Uninstalled Agents have reduced opacity but are still selectable
                            .opacity(isDetected ? 1.0 : 0.5)
                        }
                    }
                }

                // Install button
                HStack {
                    // Selected count hint
                    let selectedCount = viewModel.selectedSkillNames.count
                    Text("\(selectedCount) skill\(selectedCount == 1 ? "" : "s") selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Install") {
                        Task { await viewModel.installSelected() }
                    }
                    .disabled(viewModel.selectedSkillNames.isEmpty || viewModel.selectedAgents.isEmpty)
                    // .buttonStyle(.borderedProminent) makes button display filled prominent color style
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    /// Phase: Installing in progress
    private var installingPhase: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(viewModel.progressMessage)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    /// Phase: Installation completed
    private var completedPhase: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Installation Complete")
                .font(.headline)

            Text("\(viewModel.installedCount) skill\(viewModel.installedCount == 1 ? "" : "s") installed successfully")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                // "Install More" button: reset state and start over
                Button("Install More") {
                    viewModel.reset()
                }

                Button("Done") {
                    // dismiss() closes current sheet
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
    }

    /// Phase: Error
    /// - Parameter message: Error message
    private func errorPhase(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Something went wrong")
                .font(.headline)

            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try Again") {
                viewModel.reset()
            }

            Spacer()
        }
    }

    // MARK: - Skill Row

    /// Skill list row: checkbox + name + description + "Already installed" badge
    @ViewBuilder
    private func skillRow(_ skill: GitService.DiscoveredSkill) -> some View {
        let isAlreadyInstalled = viewModel.alreadyInstalledNames.contains(skill.id)

        HStack {
            // Checkbox
            // Toggle + checkbox style = macOS native checkbox
            Toggle(isOn: Binding(
                get: { viewModel.selectedSkillNames.contains(skill.id) },
                set: { _ in viewModel.toggleSkillSelection(skill.id) }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .disabled(isAlreadyInstalled)

            // Skill info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(skill.metadata.name.isEmpty ? skill.id : skill.metadata.name)
                        .font(.body)
                        .fontWeight(.medium)

                    // "Already installed" badge
                    if isAlreadyInstalled {
                        Text("Installed")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            // clipShape crops view shape to capsule (rounded rectangle on both ends)
                            .clipShape(Capsule())
                    }
                }

                if !skill.metadata.description.isEmpty {
                    Text(skill.metadata.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        // Row opacity: installed skills have reduced opacity
        .opacity(isAlreadyInstalled ? 0.6 : 1.0)
    }
}
