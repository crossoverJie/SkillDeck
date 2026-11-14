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

    @AppStorage(LanguageSettings.appLanguageKey) private var appLanguageRaw: String = LanguageSettings.defaultLanguage.rawValue

    @Environment(\.localizationBundle) private var localizationBundle
    @Environment(\.locale) private var locale

    /// `scenePhase` reports the lifecycle of the enclosing window scene on macOS. Watching it
    /// here means activation refreshes only happen while the Dashboard is in the view tree, not
    /// while the user is on a detail page or the app is in the background.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Single snapshot for this render pass: `filteredSkills` sorts (and, under `.usage`,
        // precomputes every usage count) on each access, so reading it twice — once for the
        // empty check and once for the `List` — would double that work on every body evaluation.
        let skills = viewModel.filteredSkills

        Group {
            if skillManager.isLoading && skillManager.skills.isEmpty {
                // Show progress indicator on first load
                ProgressView("Scanning skills...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if skills.isEmpty {
                // Empty state
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Skills Found",
                    subtitle: viewModel.searchText.isEmpty
                        ? "Install skills using npx skills add or the CLI"
                        : "No skills match your search"
                )
            } else {
                // Skill list. Two shapes on purpose:
                // - `.source` renders one `Section` per install source;
                // - `.none` keeps the ORIGINAL flat `List(data)` untouched, so flipping
                //   `groupMode` back is a one-line rollback with zero behavioural drift.
                if viewModel.groupMode == .source {
                    List(selection: $selectedSkillID) {
                        // `ForEach` over sections: each `SkillGroup` owns its own `Section`,
                        // so there is no index arithmetic anywhere.
                        ForEach(viewModel.sourceGroups(from: skills)) { group in
                            // A collapsed group keeps its `Section` (and therefore its header,
                            // which is the control the user clicks to expand it again) but
                            // renders zero rows. `[Skill]()` is needed for type inference —
                            // `[]` alone cannot tell SwiftUI which element type to use.
                            let visibleSkills: [Skill] = viewModel.isGroupCollapsed(group.id)
                                ? []
                                : group.skills

                            Section {
                                // `ForEach(group.skills)` needs `Skill: Identifiable`
                                // (already true: its id is the directory name).
                                ForEach(visibleSkills) { skill in
                                    skillRow(skill)
                                }
                            } header: {
                                groupHeader(group)
                            }
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                } else {
                    List(skills, selection: $selectedSkillID) { skill in
                        skillRow(skill)
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
        }
        .navigationTitle(navigationTitle)
        // Search bar (macOS standard search field, displayed in toolbar)
        .searchable(text: $viewModel.searchText, prompt: "Search skills...")
        // Toolbar: sorting and filtering
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        appLanguageRaw = AppLanguage.system.rawValue
                    } label: {
                        LText(key: L10nKeys.settingsLanguageSystemDefault)
                    }

                    Button {
                        appLanguageRaw = AppLanguage.english.rawValue
                    } label: {
                        LText(key: L10nKeys.settingsLanguageEnglish)
                    }

                    Button {
                        appLanguageRaw = AppLanguage.simplifiedChinese.rawValue
                    } label: {
                        LText(key: L10nKeys.settingsLanguageChineseHans)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                        Text(languageBadge)
                            .appFont(.caption2)
                            .monospaced()
                    }
                }
                .help(L10n.string(L10nKeys.dashboardLanguageMenuHelp, bundle: localizationBundle, locale: locale))
            }

            // placement: .navigation places toolbar items on the left (navigation area), default .automatic places on right
            ToolbarItemGroup(placement: .navigation) {
                Menu {
                    // A custom header view is used instead of `Section("Sort By")` because a
                    // `String` variable (from `localized(_:)`) cannot feed the LocalizedStringKey
                    // overload, and the literal would not follow the app language.
                    Section {
                        ForEach(DashboardViewModel.SortOrder.allCases, id: \.self) { order in
                            Button {
                                if viewModel.sortOrder == order {
                                    // Click selected sort field → toggle ascending/descending
                                    viewModel.sortDirection = viewModel.sortDirection.toggled
                                } else {
                                    // Click new sort field → switch to that field and use its default direction
                                    viewModel.sortOrder = order
                                    viewModel.sortDirection = order.defaultDirection
                                }
                            } label: {
                                // `Label { } icon: { }` (closure form) instead of
                                // `Label("text", systemImage:)`: `LText` is a View, so it can
                                // only be used in the closure form.
                                HStack {
                                    Label {
                                        LText(key: order.titleKey)
                                    } icon: {
                                        Image(systemName: order.iconName)
                                    }
                                    if viewModel.sortOrder == order {
                                        // Spacer pushes arrow to the right
                                        Spacer()
                                        Image(systemName: viewModel.sortDirection.iconName)
                                    }
                                }
                            }
                        }
                    } header: {
                        LText(key: L10nKeys.dashboardSortSection)
                    }

                    Section {
                        ForEach(DashboardViewModel.GroupMode.allCases, id: \.self) { mode in
                            Button {
                                viewModel.groupMode = mode
                            } label: {
                                HStack {
                                    Label {
                                        LText(key: mode.titleKey)
                                    } icon: {
                                        Image(systemName: mode.iconName)
                                    }
                                    if viewModel.groupMode == mode {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } header: {
                        LText(key: L10nKeys.dashboardGroupSection)
                    }
                } label: {
                    // Toolbar button appearance: sort icon + current sort field + direction arrow
                    // Label provides both text and icon, macOS toolbar decides which to display based on space
                    HStack(spacing: 2) {
                        Image(systemName: "line.3.horizontal.decrease")
                        // Localized key instead of the old English literal: with the menu fully
                        // translated, a raw "Usage Count" on the button looked broken.
                        LText(key: viewModel.sortOrder.titleKey)
                        Image(systemName: viewModel.sortDirection.iconName).appFont(.caption2)
                            // imageScale controls SF Symbol size
                            .imageScale(.small)
                    }
                }

                if viewModel.sortOrder == .usage, viewModel.canRefreshRelevantUsage {
                    if viewModel.isRelevantUsagePending || viewModel.isRelevantUsageRefreshing {
                        // One spinner covers both the first lazy scan and an in-place refresh.
                        // The refresh button is hidden meanwhile, so it cannot be clicked twice.
                        ProgressView()
                            .controlSize(.small)
                            .help(L10n.string(L10nKeys.usageScanning, bundle: localizationBundle, locale: locale))
                    } else {
                        // `.stale` and partial failures both increment this count; the warning
                        // stays visible while the refresh button below offers a retry.
                        if viewModel.relevantUsageFailedLogCount > 0 {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help(L10n.string(L10nKeys.usageIncompleteHelp, bundle: localizationBundle, locale: locale))
                        }

                        Button {
                            Task { await viewModel.refreshRelevantUsage() }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .controlSize(.small)
                        .help(L10n.string(L10nKeys.usageRefreshHelp, bundle: localizationBundle, locale: locale))
                        .accessibilityLabel(Text(L10n.string(L10nKeys.usageRefreshHelp, bundle: localizationBundle, locale: locale)))
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
        // Usage sorting is lazy: scan only when the user actually asks for it, and only the
        // Agents contributing to the current scope. Re-check on filter changes so switching
        // back to "all" still scans Agents that have not been touched yet.
        .onChange(of: viewModel.sortOrder) { _, newOrder in
            guard newOrder == .usage else { return }
            scanRelevantUsageIfNeeded()
        }
        .onChange(of: viewModel.selectedAgentFilter) { _, _ in
            guard viewModel.sortOrder == .usage else { return }
            scanRelevantUsageIfNeeded()
        }
        // Re-activating the window silently refreshes stale usage. The throttle lives in
        // SkillManager, so multiple windows activating at once still produce at most one scan
        // per Agent. First scans remain owned by `onChange(sortOrder)` above.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            autoRefreshUsageIfNeeded()
        }
        // `.task` runs when the view appears. It covers the case where the window is already
        // active at creation time, when `onChange(scenePhase)` will not fire. It is safe to call
        // alongside the lazy first scan: that path sets `.scanning`, which the reservation skips.
        .task {
            autoRefreshUsageIfNeeded()
        }
    }

    /// One row plus its context menu.
    ///
    /// Extracted because the grouped and flat branches both need it; duplicating the 50-line
    /// context menu in two places would guarantee the two copies drift apart.
    @ViewBuilder
    private func skillRow(_ skill: Skill) -> some View {
        SkillRowView(
            skill: skill,
            usageSummary: viewModel.usageSummary(for: skill),
            showsUnknownUsage: viewModel.sortOrder == .usage,
            usageIsScanning: viewModel.isRelevantUsagePending,
            unknownUsageHelpKey: viewModel.unknownUsageHelpKey,
            // In grouped mode the section header already states the source, so repeating it
            // inside every row would just be noise.
            showsSource: viewModel.groupMode == .none
        )
        .tag(skill.id)
        // contextMenu is macOS's right-click menu
        .contextMenu {
            Button("Open in Finder") {
                NSWorkspace.shared.selectFile(
                    nil,
                    inFileViewerRootedAtPath: skill.canonicalURL.path
                )
            }

            // Branch on the freshest state, not the row's `skill` snapshot.
            // A broken skill has no content file, so it gets Delete + (conditional)
            // Reinstall instead of a Disable/Enable toggle.
            if skillManager.latest(id: skill.id)?.isBroken == true {
                Divider()
                Button("Delete", role: .destructive) {
                    viewModel.requestDelete(skill: skill)
                }
                // Keep visibility consistent with SkillManager.reinstallBrokenSkill:
                // only a github lockEntry can be auto-rebuilt. Otherwise the detail
                // page shows the manual-reinstall hint instead of a dead button.
                if skillManager.latest(id: skill.id)?.lockEntry?.sourceType == "github" {
                    Button {
                        Task { await viewModel.reinstallBrokenSkill(skill) }
                    } label: {
                        LText(key: L10nKeys.skillBrokenReinstall)
                    }
                }
            } else {
                Divider()
                let isDisabled = skillManager.latest(id: skill.id)?.isDisabled ?? false
                // Only the id is forwarded; SkillManager derives the direction
                // from latest(id:). We intentionally do NOT disable this item:
                // clicking an ineligible skill surfaces a precise localized reason
                // (externalLocation / duplicateRealCopy / ...) in the overlay.
                Button {
                    Task { await viewModel.toggleSkillDisabled(id: skill.id) }
                } label: {
                    LText(key: isDisabled
                          ? L10nKeys.skillEnableAction
                          : L10nKeys.skillDisableAction)
                }
                Divider()
                Button("Delete", role: .destructive) {
                    viewModel.requestDelete(skill: skill)
                }
            }
        }
    }

    /// Section header: disclosure chevron + source label + skill count, plus an "open source"
    /// button for sources that have a web page.
    ///
    /// Clicking the chevron/title/count area collapses or expands the section; the whole group is
    /// one button so the hit target is the full header width (`.contentShape` makes the empty
    /// gap between the labels clickable too). Font is `subheadline` — `caption` was too small to
    /// read at a glance and this is the only structural label in the list.
    private func groupHeader(_ group: DashboardViewModel.SkillGroup) -> some View {
        // `switch` over the `GroupTitle` enum. Swift resolves the localized case here at render
        // time, so switching the app language re-renders headers like every other string.
        // (This is a `switch` expression — Swift 5.9 allows the whole thing on the right-hand
        // side of a `let`.)
        let title: String = switch group.title {
        case .literal(let text): text
        case .localized(let key): localized(key)
        }
        let isCollapsed = viewModel.isGroupCollapsed(group.id)

        // ONE tooltip for the whole header, built here instead of stacking `.help` on both the
        // parent and the child. The toggle button covers nearly the full header width (it ends
        // in `Spacer(minLength: 0)`), so two overlapping `.help` regions would mean AppKit shows
        // only one of them and the other becomes unreachable — which silently killed the local
        // path tooltip (`group.helpText`).
        var collapseHelpParts = [localized(isCollapsed
                                           ? L10nKeys.dashboardGroupExpand
                                           : L10nKeys.dashboardGroupCollapse)]
        if let detail = group.helpText { collapseHelpParts.append(detail) }
        let collapseHelp = collapseHelpParts.joined(separator: "\n")

        return HStack(spacing: 6) {
            Button {
                viewModel.toggleGroupCollapsed(group.id)
            } label: {
                HStack(spacing: 6) {
                    // Chevron mirrors the state: pointing right = collapsed, down = expanded.
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .appFont(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    // `%d` needs `String(format:)`; `LText` only takes keys without arguments.
                    Text(String(format: localized(L10nKeys.dashboardGroupSkillCountFormat), group.skills.count))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            // `.plain` removes the button chrome so the header still reads as a label rather
            // than a pushed button (`.borderless` would tint and inset it).
            .buttonStyle(.plain)
            .help(collapseHelp)

            if let webURL = group.webURL {
                Button {
                    // `NSWorkspace.open` is the macOS "open with the default handler" call;
                    // for an https URL that is the user's browser.
                    NSWorkspace.shared.open(webURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .appFont(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("\(localized(L10nKeys.dashboardGroupOpenSource))\n\(webURL.absoluteString)")
            }
        }
    }

    /// Same tiny wrapper as `SkillRowView.localized(_:)`: SwiftUI `@Environment` values are only
    /// reachable from the view, and `L10n.string` needs both bundle and locale. It is not a
    /// global function on purpose — the repo keeps localization helpers view-local.
    private func localized(_ key: String) -> String {
        L10n.string(key, bundle: localizationBundle, locale: locale)
    }

    private func scanRelevantUsageIfNeeded() {
        guard viewModel.hasUnscannedRelevantUsage else { return }
        Task {
            await skillManager.loadSkillUsage(
                agentTypes: Set(viewModel.relevantUsageAgents)
            )
        }
    }

    private func autoRefreshUsageIfNeeded() {
        // The Dashboard list stays mounted while a detail is open in the split view's right
        // pane, so window activation must not be treated as "Dashboard is focused".
        let isDetailOpen = selectedSkillID != nil
        Task {
            await viewModel.autoRefreshRelevantUsage(isDetailOpen: isDetailOpen)
        }
    }

    private var navigationTitle: String {
        if let agent = viewModel.selectedAgentFilter {
            return agent.displayName
        }
        return "All Skills"
    }

    private var languageBadge: String {
        switch AppLanguage(storedRawValue: appLanguageRaw) {
        case .system:
            return "Auto"
        case .english:
            return "EN"
        case .simplifiedChinese:
            return "中"
        }
    }

}
