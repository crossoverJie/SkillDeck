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

    var body: some View {
        VStack(spacing: 0) {
            // This content-level action stays visible even when the toolbar overflows or disabling
            // the final active skill leaves the dashboard in its empty state.
            if !viewModel.disabledSkills.isEmpty {
                HStack {
                    Button {
                        viewModel.showsDisabledSkills = true
                    } label: {
                        Label(L10n.currentFormat(L10nKeys.dashboardDisabledCount, viewModel.disabledSkills.count), systemImage: "archivebox")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }

            // Segmented controls are the native compact control for mutually exclusive display modes.
            Picker(L10n.currentString(L10nKeys.dashboardScope), selection: $viewModel.scopeFilter) {
                ForEach(DashboardScopeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if viewModel.scopeFilter == .project {
                Picker(L10n.currentString(L10nKeys.dashboardProject), selection: $viewModel.selectedProjectFilterID) {
                    Text(L10n.currentString(L10nKeys.dashboardAllProjects)).tag(String?.none)
                    ForEach(viewModel.projectManager.projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Group {
                if skillManager.isLoading && skillManager.skills.isEmpty {
                    // Show progress indicator on first load
                    ProgressView("Scanning skills...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.filteredItems.isEmpty {
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
                    List(viewModel.filteredItems, selection: $selectedSkillID) { item in
                        SkillRowView(skill: item.skill, projectName: projectName(for: item))
                            .tag(item.id)
                            // contextMenu is macOS's right-click menu
                            .contextMenu {
                                Button("Open in Finder") {
                                    NSWorkspace.shared.selectFile(
                                        nil,
                                        inFileViewerRootedAtPath: item.skill.canonicalURL.path
                                    )
                                }
                                Divider()  // Menu separator
                                Button(L10n.currentString(L10nKeys.dashboardDisable)) {
                                    viewModel.requestDisable(item: item)
                                }
                            }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
        }
        .navigationTitle(navigationTitle)
        // Project changes refresh the source-skill rows without waiting for an app relaunch.
        .task(id: viewModel.projectRevision) {
            await viewModel.reloadProjectSkills()
            viewModel.reloadDisabledSkills()
        }
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
                        Image(systemName: viewModel.sortDirection.iconName).appFont(.caption2)
                            // imageScale controls SF Symbol size
                            .imageScale(.small)
                    }
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.reloadDisabledSkills()
                    viewModel.showsDisabledSkills = true
                } label: {
                    Label(L10n.currentString(L10nKeys.dashboardDisabledTitle), systemImage: "archivebox")
                }
                .help(L10n.currentString(L10nKeys.dashboardDisabledHelp))
            }
        }
        // Disable confirmation dialog
        // .alert similar to Android's AlertDialog or Web's confirm()
        .alert(L10n.currentString(L10nKeys.dashboardDisable), isPresented: $viewModel.showDisableConfirmation) {
            Button(L10n.currentString(L10nKeys.commonCancel), role: .cancel) {
                viewModel.cancelDelete()
            }
            Button(L10n.currentString(L10nKeys.dashboardDisable)) {
                Task { await viewModel.confirmDelete() }
            }
        } message: {
            if let item = viewModel.itemToDisable {
                Text(L10n.currentFormat(L10nKeys.dashboardDisableDescription, item.skill.displayName))
            }
        }
        .sheet(isPresented: $viewModel.showsDisabledSkills) {
            DisabledSkillsSheet(viewModel: viewModel)
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

    private func projectName(for item: DashboardSkillItem) -> String? {
        guard case .project(let projectSkill) = item.origin else { return nil }
        return projectSkill.project.name
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
