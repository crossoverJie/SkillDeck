import SwiftUI

/// ContentView is the root view of the application
///
/// NavigationSplitView is macOS's three-column navigation layout (similar to Apple Mail):
/// - Left column (sidebar): navigation menu
/// - Middle column (content): list
/// - Right column (detail): details
///
/// @Environment retrieves injected objects from the View tree (similar to React's useContext)
/// SkillManager is injected via .environment() in SkillDeckApp.swift
struct ContentView: View {

    @Environment(SkillManager.self) private var skillManager

    /// Sidebar visibility state for NavigationSplitView
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    /// Currently selected sidebar item
    @State private var selectedSidebarItem: SidebarItem? = .dashboard

    /// Currently selected skill ID (used for navigation to detail page)
    @State private var selectedSkillID: String?

    /// Dashboard ViewModel
    @State private var dashboardVM: DashboardViewModel?

    /// Detail ViewModel
    @State private var detailVM: SkillDetailViewModel?

    /// F09: Registry browser ViewModel
    /// Created alongside other VMs in .task; manages leaderboard browsing and search
    @State private var registryVM: RegistryBrowserViewModel?

    /// Custom repository ViewModels — one per configured repository, keyed by UUID.
    ///
    /// Dictionary lookup by UUID maps each `SidebarItem.customRepo(id)` selection to its VM.
    /// Created/refreshed in .task whenever the repositories list changes.
    /// Using [UUID: RepositoryBrowserViewModel] instead of [SkillRepository: VM] because
    /// SkillRepository can change (user renames it), but the UUID stays stable.
    @State private var repoVMs: [UUID: RepositoryBrowserViewModel] = [:]

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Left column: sidebar navigation
            // navigationSplitViewColumnWidth constrains sidebar width range,
            // preventing content from being clipped when sidebar is too narrow after window restoration
            SidebarView(selection: $selectedSidebarItem)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } content: {
            // Middle column: content varies based on sidebar selection
            // F09: When "Registry" is selected, show RegistryBrowserView instead of DashboardView
            if selectedSidebarItem == .registry {
                // F09: Registry browser — browse and search skills.sh catalog
                if let vm = registryVM {
                    RegistryBrowserView(viewModel: vm)
                        // Registry needs wider column for skill info + install buttons
                        .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
                }
            } else if case .customRepo(let repoID) = selectedSidebarItem,
                      let vm = repoVMs[repoID] {
                // Custom repository browser: shows skills in the selected user-configured repo
                RepositoryBrowserView(viewModel: vm)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
            } else {
                // Default: show skill dashboard list
                if let vm = dashboardVM {
                    DashboardView(viewModel: vm, selectedSkillID: $selectedSkillID)
                        // Constrain middle column (skill list) width range,
                        // preventing content from being squeezed when first opening
                        .navigationSplitViewColumnWidth(min: 250, ideal: 320, max: 450)
                }
            }
        } detail: {
            // Right column: detail view varies based on sidebar selection
            if selectedSidebarItem == .registry {
                // F09: Show registry skill detail when a registry skill is selected
                if let vm = registryVM, let skill = vm.selectedSkill {
                    RegistrySkillDetailView(
                        skill: skill,
                        isInstalled: vm.isInstalled(skill),
                        onInstall: { vm.installSkill(skill) },
                        viewModel: vm
                    )
                } else {
                    EmptyStateView(
                        icon: "globe",
                        title: "Select a Skill",
                        subtitle: "Choose a skill from the registry to view its details"
                    )
                }
            } else if case .customRepo = selectedSidebarItem {
                if case .customRepo(let repoID) = selectedSidebarItem,
                   let vm = repoVMs[repoID],
                   let skill = vm.selectedSkill {
                    RepositorySkillDetailView(
                        skill: skill,
                        repository: vm.repository,
                        isInstalled: vm.isInstalled(skill),
                        canInstall: vm.canInstallFromLocal,
                        installDisabledReason: vm.installDisabledReason,
                        onInstall: { vm.installSkill(skill) }
                    )
                } else {
                    EmptyStateView(
                        icon: "archivebox",
                        title: "Select a Skill",
                        subtitle: "Choose a skill from the repository to view its details"
                    )
                }
            } else if let skillID = selectedSkillID, let vm = detailVM {
                SkillDetailView(skillID: skillID, viewModel: vm)
                    // .id(skillID) forces SwiftUI to destroy and recreate the detail view
                    // whenever the selected skill changes, rather than reusing the same view
                    // instance with an implicit cross-fade transition.
                    // Without this, NavigationSplitView keeps the old content visible during
                    // its built-in transition animation, causing the 1-3s "stale content" delay.
                    // This is equivalent to React's `key` prop — a changed key tells SwiftUI
                    // "this is a completely new view", ensuring immediate visual feedback.
                    .id(skillID)
            } else {
                EmptyStateView(
                    icon: "square.stack.3d.up",
                    title: "Select a Skill",
                    subtitle: "Choose a skill from the list to view its details"
                )
            }
        }
        // .task executes async task when View first appears (similar to React's useEffect([], ...))
        .task {
            dashboardVM = DashboardViewModel(skillManager: skillManager)
            detailVM = SkillDetailViewModel(skillManager: skillManager)
            // F09: Initialize registry browser ViewModel
            registryVM = RegistryBrowserViewModel(skillManager: skillManager)
            await skillManager.refresh()
            // Build repoVMs for any repositories that were loaded during refresh
            rebuildRepoVMs()
            // Auto-check for updates on app launch (subject to 4-hour interval limit, not every launch requests GitHub API)
            await skillManager.checkForAppUpdate()
        }
        // Keep repoVMs in sync when the repositories list changes
        // (e.g., user adds or removes a repository in Settings)
        .onChange(of: skillManager.repositories) { _, _ in
            rebuildRepoVMs()
        }
        // .onChange(of:) triggers closure when specified value changes (similar to React's useEffect with dependency array)
        // When user clicks sidebar navigation item, maps selection to Agent filter and syncs to DashboardViewModel
        // Implements sidebar click → Dashboard list filter linkage effect
        .onChange(of: selectedSidebarItem) { _, newValue in
            dashboardVM?.selectedAgentFilter = newValue?.agentFilter
        }
    }

    // MARK: - Private Helpers

    /// Create or update the repoVMs dictionary to match the current repositories list.
    ///
    /// - Adds a new RepositoryBrowserViewModel for any newly added repository
    /// - Removes VMs for repositories that were deleted
    /// - Keeps existing VMs for unchanged repositories (preserves their loaded state)
    ///
    /// Called on initial app load and whenever skillManager.repositories changes.
    private func rebuildRepoVMs() {
        // Add VMs for new repos
        for repo in skillManager.repositories {
            if let vm = repoVMs[repo.id] {
                // Keep existing VM state, but refresh repo metadata snapshot.
                vm.updateRepository(repo)
            } else {
                repoVMs[repo.id] = RepositoryBrowserViewModel(
                    repository: repo,
                    skillManager: skillManager
                )
            }
        }

        // Remove VMs for deleted repos
        let currentIDs = Set(skillManager.repositories.map(\.id))
        for id in repoVMs.keys where !currentIDs.contains(id) {
            repoVMs.removeValue(forKey: id)
        }
    }
}
