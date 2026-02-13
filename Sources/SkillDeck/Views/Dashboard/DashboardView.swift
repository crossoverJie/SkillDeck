import SwiftUI

/// DashboardView is the skill list page (F02)
///
/// Displays all installed skills, supporting search, filtering, and sorting
struct DashboardView: View {

    /// @Bindable allows @Observable object properties to be prefixed with $ to create Binding
    /// For example, $viewModel.searchText creates a Binding<String>
    @Bindable var viewModel: DashboardViewModel
    @Binding var selectedSkillID: String?
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        Group {
            if skillManager.isLoading && skillManager.skills.isEmpty {
                // Show progress indicator on first load
                ProgressView("Scanning skills...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredSkills.isEmpty {
                // Empty state
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Skills Found",
                    subtitle: viewModel.searchText.isEmpty
                        ? "Install skills using npx skills add or the CLI"
                        : "No skills match your search"
                )
            } else {
                // Skill list
                List(viewModel.filteredSkills, selection: $selectedSkillID) { skill in
                    SkillRowView(skill: skill)
                        .tag(skill.id)
                        // contextMenu is macOS's right-click menu
                        .contextMenu {
                            Button("Open in Finder") {
                                NSWorkspace.shared.selectFile(
                                    nil,
                                    inFileViewerRootedAtPath: skill.canonicalURL.path
                                )
                            }
                            Divider()  // Menu separator
                            Button("Delete", role: .destructive) {
                                viewModel.requestDelete(skill: skill)
                            }
                        }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .navigationTitle(navigationTitle)
        // Search bar (macOS standard search field, displayed in toolbar)
        .searchable(text: $viewModel.searchText, prompt: "Search skills...")
        // Toolbar: sorting and filtering
        .toolbar {
            // placement: .navigation places toolbar items on the left (navigation area), default .automatic places on right
            ToolbarItemGroup(placement: .navigation) {
                Menu {
                    // Section creates titled groups in menus, similar to Android's menu group
                    Section("Sort By") {
                        ForEach(DashboardViewModel.SortOrder.allCases, id: \.self) { order in
                            Button {
                                if viewModel.sortOrder == order {
                                    // Click selected sort field → toggle ascending/descending
                                    viewModel.sortDirection = viewModel.sortDirection.toggled
                                } else {
                                    // Click new sort field → switch to that field, reset to ascending
                                    viewModel.sortOrder = order
                                    viewModel.sortDirection = .ascending
                                }
                            } label: {
                                // HStack horizontal layout: icon + text + sort direction arrow
                                HStack {
                                    Label(order.rawValue, systemImage: order.iconName)
                                    if viewModel.sortOrder == order {
                                        // Spacer pushes arrow to the right
                                        Spacer()
                                        Image(systemName: viewModel.sortDirection.iconName)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    // Toolbar button appearance: sort icon + current sort field + direction arrow
                    // Label provides both text and icon, macOS toolbar decides which to display based on space
                    HStack(spacing: 2) {
                        Image(systemName: "line.3.horizontal.decrease")
                        Text(viewModel.sortOrder.rawValue)
                        Image(systemName: viewModel.sortDirection.iconName)
                            .font(.caption2)
                            // imageScale controls SF Symbol size
                            .imageScale(.small)
                    }
                }
            }
        }
        // Delete confirmation dialog
        // .alert similar to Android's AlertDialog or Web's confirm()
        .alert("Delete Skill", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
            Button("Delete", role: .destructive) {
                Task { await viewModel.confirmDelete() }
            }
        } message: {
            if let skill = viewModel.skillToDelete {
                Text("Are you sure you want to delete \"\(skill.displayName)\"? This will remove the skill directory and all symlinks. This action cannot be undone.")
            }
        }
        // Error message
        .overlay(alignment: .bottom) {
            if let error = skillManager.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error)
                    Spacer()
                    Button("Dismiss") {
                        skillManager.errorMessage = nil
                    }
                    .buttonStyle(.borderless)
                }
                .padding()
                .background(.red.opacity(0.1))
                .cornerRadius(8)
                .padding()
            }
        }
    }

    private var navigationTitle: String {
        if let agent = viewModel.selectedAgentFilter {
            return agent.displayName
        }
        return "All Skills"
    }
}
