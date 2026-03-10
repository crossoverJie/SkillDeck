import SwiftUI

/// LocalImportView is the sheet UI for importing skills from local directories
///
/// Follows the same layout pattern as SkillInstallView:
/// VStack with headerBar + phase-switched content, displayed as a .sheet() modal.
///
/// Phase flow: selectPath → validating → selectAgents → importing → completed | error
struct LocalImportView: View {

    /// ViewModel manages the import process state
    /// @Bindable allows @Observable object properties to create Binding (two-way binding)
    @Bindable var viewModel: LocalImportViewModel

    /// Get dismiss action from environment, used to close sheet
    /// @Environment(\.dismiss) is SwiftUI's standard way to close currently presented view
    @Environment(\.dismiss) private var dismiss

    /// Get SkillManager from environment (for checking detected Agents)
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        VStack(spacing: 0) {
            // Header bar (common to all phases)
            headerBar

            Divider()

            // Display different content based on current phase
            // Swift's switch is an expression, can be used directly in ViewBuilder
            switch viewModel.phase {
            case .selectPath:
                selectPathPhase
            case .validating:
                validatingPhase
            case .selectAgents:
                selectAgentsPhase
            case .importing:
                importingPhase
            case .completed:
                completedPhase
            case .error(let message):
                errorPhase(message)
            }
        }
        // Sheet modal minimum size (macOS standard practice)
        .frame(minWidth: 500, minHeight: 350)
    }

    // MARK: - Header

    /// Header bar with title and close button (common to all phases)
    private var headerBar: some View {
        HStack {
            Text("Import Local Skill").appFont(.headline)
            Spacer()
            // Close button
            Button {
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

    /// Phase 1: Select a local directory
    /// Shows a folder icon, description text, and a "Select Folder..." button
    private var selectPathPhase: some View {
        VStack(spacing: 16) {
            Spacer()

            // Folder icon (large, decorative)
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Select a local directory containing SKILL.md").appFont(.subheadline)
                .foregroundStyle(.secondary)

            // "Select Folder..." button triggers NSOpenPanel
            Button("Select Folder...") {
                viewModel.openFolderPicker()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }

    /// Phase: Validating directory (shows spinner)
    private var validatingPhase: some View {
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

    /// Phase 2: Select target Agents and confirm import
    /// Shows skill preview card + overwrite warning + Agent grid + Import button
    private var selectAgentsPhase: some View {
        VStack(spacing: 0) {
            // Skill preview card (scrollable if content is tall)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Skill name and description preview
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.skillMetadata?.name ?? viewModel.skillName).appFont(.title3)
                            .fontWeight(.semibold)

                        if let desc = viewModel.skillMetadata?.description, !desc.isEmpty {
                            Text(desc).appFont(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }

                    // Source path display (shows where the skill is being imported from)
                    if let dirURL = viewModel.selectedDirectoryURL {
                        HStack(spacing: 4) {
                            Image(systemName: "folder").appFont(.caption)
                                .foregroundStyle(.secondary)
                            Text(dirURL.path).appFont(.caption)
                                .foregroundStyle(.secondary)
                                // lineLimit(1) + truncationMode(.middle) truncates long paths in the middle
                                // e.g., "/Users/.../very-long-path/skill-dir" → shows start and end with ... in middle
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    // Overwrite warning: shown when a skill with the same name already exists
                    if viewModel.alreadyExists {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("A skill named \"\(viewModel.skillName)\" already exists and will be overwritten.").appFont(.caption)
                                .foregroundStyle(.orange)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        // clipShape rounds the corners of the background
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding()
            }

            Divider()

            // Agent selection area + Import button
            VStack(spacing: 12) {
                // Agent selection grid (same layout as SkillInstallView)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Install to:").appFont(.subheadline)
                        .foregroundStyle(.secondary)

                    // LazyVGrid adapts column width, automatically wraps based on available space
                    // adaptive(minimum: 120) means each column is at least 120pt
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(AgentType.allCases) { agentType in
                            let isDetected = skillManager.agents.first { $0.type == agentType }?.isInstalled == true
                            // Toggle is macOS checkbox component
                            Toggle(isOn: Binding(
                                get: { viewModel.selectedAgents.contains(agentType) },
                                set: { _ in viewModel.toggleAgentSelection(agentType) }
                            )) {
                                Label(agentType.displayName, systemImage: agentType.iconName).appFont(.caption)
                            }
                            .toggleStyle(.checkbox)
                            // Uninstalled Agents have reduced opacity but are still selectable
                            .opacity(isDetected ? 1.0 : 0.5)
                        }
                    }
                }

                // Import button
                HStack {
                    Spacer()

                    Button("Import") {
                        Task { await viewModel.importSkill() }
                    }
                    .disabled(viewModel.selectedAgents.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    /// Phase: Importing in progress (shows spinner)
    private var importingPhase: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(viewModel.progressMessage)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    /// Phase: Import completed (green checkmark + action buttons)
    private var completedPhase: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Import Complete").appFont(.headline)

            Text("\"\(viewModel.skillName)\" has been imported successfully")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                // "Import More" button: reset state and start over
                Button("Import More") {
                    viewModel.reset()
                }

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
    }

    /// Phase: Error (orange triangle + error message + retry button)
    /// - Parameter message: Error message to display
    private func errorPhase(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Something went wrong").appFont(.headline)

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
}
