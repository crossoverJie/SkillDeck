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
    @Environment(\.localizationBundle) private var localizationBundle
    @Environment(\.locale) private var locale

    /// Sidebar visibility state for NavigationSplitView
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    /// Currently selected sidebar item
    @State private var selectedSidebarItem: SidebarItem? = .dashboard

    /// ProjectManager is independent from SkillManager because project skills must not be
    /// deduplicated with global skills that happen to share the same directory name.
    @State private var projectManager: ProjectManager?

    /// Global sync uses the same manager with the user home directory as a fixed project root.
    @State private var globalSyncManager: ProjectManager?

    /// Currently selected skill ID (used for navigation to detail page)
    @State private var selectedSkillID: String?

    /// Dashboard ViewModel
    @State private var dashboardVM: DashboardViewModel?

    /// Detail ViewModel
    @State private var detailVM: SkillDetailViewModel?

    /// F09: Registry browser ViewModel
    /// Created alongside other VMs in .task; manages leaderboard browsing and search
    @State private var registryVM: RegistryBrowserViewModel?

    /// Dedicated ClawHub browser ViewModel
    /// Kept separate from the skills.sh registry VM because ClawHub has its own API contract and install flow.
    @State private var clawHubVM: ClawHubBrowserViewModel?

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
            if selectedSidebarItem == .globalSync {
                if let globalSyncManager {
                    GlobalSkillSourceList(manager: globalSyncManager)
                        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
                }
            } else if selectedSidebarItem == .projects {
                if let projectManager {
                    ProjectTargetList(manager: projectManager)
                        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
                }
            } else if selectedSidebarItem == .registry {
                // F09: Registry browser — browse and search skills.sh catalog
                if let vm = registryVM {
                    RegistryBrowserView(viewModel: vm)
                        // Registry needs wider column for skill info + install buttons
                        .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
                }
            } else if selectedSidebarItem == .clawHub {
                if let vm = clawHubVM {
                    ClawHubBrowserView(viewModel: vm)
                        .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
                }
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
            if selectedSidebarItem == .globalSync {
                if let globalSyncManager {
                    ProjectSyncDetail(manager: globalSyncManager)
                } else {
                    EmptyStateView(icon: "link", title: L10n.string(L10nKeys.sidebarGlobalSync, bundle: localizationBundle, locale: locale), subtitle: L10n.string(L10nKeys.contentPreparingGlobalSync, bundle: localizationBundle, locale: locale))
                }
            } else if selectedSidebarItem == .projects {
                if let projectManager {
                    ProjectSyncDetail(manager: projectManager)
                } else {
                    EmptyStateView(icon: "folder", title: L10n.string(L10nKeys.sidebarProjects, bundle: localizationBundle, locale: locale), subtitle: L10n.string(L10nKeys.contentPreparingProjects, bundle: localizationBundle, locale: locale))
                }
            } else if selectedSidebarItem == .registry {
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
                        title: L10n.string(L10nKeys.emptySelectSkillTitle, bundle: localizationBundle, locale: locale),
                        subtitle: L10n.string(L10nKeys.emptySelectSkillSubtitleRegistry, bundle: localizationBundle, locale: locale)
                    )
                }
            } else if selectedSidebarItem == .clawHub {
                if let vm = clawHubVM, let skill = vm.selectedSkill {
                    ClawHubSkillDetailView(
                        skill: skill,
                        isInstalled: vm.isInstalled(skill),
                        isInstalling: vm.isInstalling(skill),
                        onInstall: { vm.installSkill(skill) },
                        viewModel: vm
                    )
                } else {
                    EmptyStateView(
                        icon: "shippingbox",
                        title: L10n.string(L10nKeys.emptySelectSkillTitle, bundle: localizationBundle, locale: locale),
                        subtitle: L10n.string(L10nKeys.emptySelectSkillSubtitleClawHub, bundle: localizationBundle, locale: locale)
                    )
                }
            } else if let itemID = selectedSkillID, let dashboardVM {
                if let item = dashboardVM.item(id: itemID) {
                    switch item.origin {
                    case .global:
                        if let detailVM {
                            SkillDetailView(skillID: item.skill.id, viewModel: detailVM)
                        }
                    case .project(let projectSkill):
                        ProjectSkillDetailView(row: projectSkill.row)
                    }
                } else {
                    EmptyStateView(
                        icon: "square.stack.3d.up",
                        title: L10n.string(L10nKeys.emptySelectSkillTitle, bundle: localizationBundle, locale: locale),
                        subtitle: L10n.string(L10nKeys.emptySelectSkillSubtitleList, bundle: localizationBundle, locale: locale)
                    )
                }
            } else {
                EmptyStateView(
                    icon: "square.stack.3d.up",
                    title: L10n.string(L10nKeys.emptySelectSkillTitle, bundle: localizationBundle, locale: locale),
                    subtitle: L10n.string(L10nKeys.emptySelectSkillSubtitleList, bundle: localizationBundle, locale: locale)
                )
            }
        }
        // .task executes async task when View first appears (similar to React's useEffect([], ...))
        .task {
            let manager = ProjectManager()
            manager.reload()
            projectManager = manager
            dashboardVM = DashboardViewModel(skillManager: skillManager, projectManager: manager)
            detailVM = SkillDetailViewModel(skillManager: skillManager)
            let globalManager = ProjectManager(fixedProject: ManagedProject(rootPath: NSHomeDirectory(), usesConfiguredGlobalSource: true))
            globalManager.reload()
            globalSyncManager = globalManager
            // F09: Initialize registry browser ViewModel
            registryVM = RegistryBrowserViewModel(skillManager: skillManager)
            clawHubVM = ClawHubBrowserViewModel(skillManager: skillManager)
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
        .alert(
            item: Binding(
                get: { skillManager.translationPackPrompt },
                set: { skillManager.translationPackPrompt = $0 }
            )
        ) { prompt in
            Alert(
                title: Text(prompt.title),
                message: Text(prompt.message),
                primaryButton: .default(Text("知道了")) {
                    skillManager.dismissTranslationPackPrompt()
                },
                secondaryButton: .default(Text("下次不再提示")) {
                    skillManager.dontShowTranslationPackPromptAgain()
                }
            )
        }
    }
}
