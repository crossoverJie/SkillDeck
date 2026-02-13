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

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Left column: sidebar navigation
            // navigationSplitViewColumnWidth constrains sidebar width range,
            // preventing content from being clipped when sidebar is too narrow after window restoration
            SidebarView(selection: $selectedSidebarItem)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } content: {
            // Middle column: skill list
            if let vm = dashboardVM {
                DashboardView(viewModel: vm, selectedSkillID: $selectedSkillID)
                    // Constrain middle column (skill list) width range,
                    // preventing content from being squeezed when first opening
                    .navigationSplitViewColumnWidth(min: 250, ideal: 320, max: 450)
            }
        } detail: {
            // Right column: skill details
            if let skillID = selectedSkillID, let vm = detailVM {
                SkillDetailView(skillID: skillID, viewModel: vm)
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
            await skillManager.refresh()
            // Auto-check for updates on app launch (subject to 4-hour interval limit, not every launch requests GitHub API)
            await skillManager.checkForAppUpdate()
        }
        // .onChange(of:) triggers closure when specified value changes (similar to React's useEffect with dependency array)
        // When user clicks sidebar navigation item, maps selection to Agent filter and syncs to DashboardViewModel
        // Implements sidebar click → Dashboard list filter linkage effect
        .onChange(of: selectedSidebarItem) { _, newValue in
            dashboardVM?.selectedAgentFilter = newValue?.agentFilter
        }
    }
}
