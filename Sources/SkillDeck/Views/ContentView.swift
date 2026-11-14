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
            //
            // navigationSplitViewColumnWidth(min:ideal:max:) sets the range the user can DRAG the
            // column splitter within. Important SwiftUI/macOS detail: this range is only enforced
            // for user drags — a width restored from saved window state can fall outside it, so
            // the toolbar below must tolerate widths down to `min` (see SidebarView.toolbar).
            //
            // Why min was raised 180 → 280: the sidebar's own toolbar items are laid out INSIDE
            // the sidebar column band, and macOS reserves ~117pt (traffic lights + leading inset)
            // plus ~47pt (the sidebar-collapse button), so the usable band is roughly
            // (width - 164pt). The two split buttons in SidebarView.toolbar need ~118pt plus that
            // fixed overhead, i.e. a sidebar of at least ~280pt; at the old 180pt minimum the band
            // was ~16pt and NO toolbar item fit — that minimum was effectively meaningless.
            //
            // Why max was raised 300 → 400: the four old toolbar icons (three 44pt icons + the 57pt
            // install menu + 47pt collapse button) needed ~353pt of the 300pt band, so the last icon
            // (Refresh) was ALWAYS pushed into the overflow menu. The compacted toolbar (see
            // SidebarView) needs ~118pt, leaving comfortable slack here for future additions.
            SidebarView(selection: $selectedSidebarItem)
                .navigationSplitViewColumnWidth(min: 280, ideal: 290, max: 400)
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
            } else if selectedSidebarItem == .clawHub {
                if let vm = clawHubVM {
                    ClawHubBrowserView(viewModel: vm)
                        .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
                }
            } else {
                // Default: show skill dashboard list
                if let vm = dashboardVM {
                    DashboardView(viewModel: vm, selectedSkillID: $selectedSkillID)
                        // Skill list column width range.
                        // - `min` keeps the original intent of the old max-only clamping: the list
                        //   must not be squeezed when the window is narrow or state is restored.
                        // - `ideal` decides the width on first launch.
                        // - `max` was 450, which users hit immediately and then could not drag past,
                        //   forcing long skill names onto two lines. 720 gives them room while still
                        //   stopping the Markdown detail pane (which has no min width of its own)
                        //   from being squeezed to unreadable.
                        .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 720)
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
            } else if let skillID = selectedSkillID, let vm = detailVM {
                SkillDetailView(skillID: skillID, viewModel: vm)
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
            dashboardVM = DashboardViewModel(skillManager: skillManager)
            detailVM = SkillDetailViewModel(skillManager: skillManager)
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
