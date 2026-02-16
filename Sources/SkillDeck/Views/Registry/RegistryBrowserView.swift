import SwiftUI

/// RegistryBrowserView is the F09 Registry Browser main view
///
/// Displays the skills.sh catalog with two modes:
/// 1. **Leaderboard browsing**: Category tabs (All Time / Trending 24h / Hot) showing ranked skills
/// 2. **Search**: Type-ahead search using the skills.sh API
///
/// This view occupies the "content" column (middle pane) of the NavigationSplitView,
/// replacing DashboardView when the "Registry" sidebar item is selected.
///
/// @Bindable is used instead of @Binding for @Observable objects — it allows creating
/// two-way bindings ($viewModel.property) from @Observable class properties.
/// This is the macOS 14+ replacement for @ObservedObject + @Published.
struct RegistryBrowserView: View {

    /// ViewModel manages the state for browsing, searching, and installing
    /// @Bindable creates two-way bindings for @Observable object properties
    @Bindable var viewModel: RegistryBrowserViewModel

    /// SkillManager from environment (needed to pass into install sheet)
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        VStack(spacing: 0) {
            // Category tabs (All Time / Trending 24h / Hot)
            // Hidden when search is active — search results replace the leaderboard
            if !viewModel.isSearchActive {
                categoryTabs
                Divider()
            }

            // Main content area
            if viewModel.isLoading && viewModel.displayedSkills.isEmpty {
                // Initial loading state: show centered spinner
                // ProgressView with a string label shows a spinning indicator with text below
                loadingView
            } else if viewModel.displayedSkills.isEmpty {
                // No data: show appropriate empty state
                emptyState
            } else {
                // Skill list
                skillList
            }
        }
        .navigationTitle("Skill Registry")
        // .searchable adds a native macOS search bar in the toolbar area
        // The text binding ($viewModel.searchText) updates as user types.
        // `prompt` is the placeholder text shown when the search field is empty.
        // This is the standard macOS search pattern (similar to Finder's search bar).
        .searchable(text: $viewModel.searchText, prompt: "Search skills.sh...")
        // .onChange(of:) triggers closure when the observed value changes
        // Here we call the debounced search handler on each keystroke
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.onSearchTextChanged()
        }
        .toolbar {
            // Refresh button in toolbar
            ToolbarItem {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh registry data")
            }

            // "Open in Browser" button — opens skills.sh in the default web browser
            ToolbarItem {
                Button {
                    // NSWorkspace.shared.open() opens a URL in the default browser
                    // This is macOS-specific API (similar to Desktop.browse() in Java)
                    if let url = URL(string: "https://skills.sh") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                }
                .help("Open skills.sh in browser")
            }
        }
        // .task runs async code when the view first appears
        .task {
            await viewModel.onAppear()
        }
        // Install sheet — reuses the existing SkillInstallView (F10)
        // .sheet(item:) shows the sheet when installVM is non-nil
        // onDismiss is called when the sheet closes (cleanup temp files + sync installed status)
        .sheet(item: $viewModel.installVM, onDismiss: {
            viewModel.installVM?.cleanup()
            viewModel.installVM = nil
            // Sync installed skill IDs so badges update immediately after install
            viewModel.syncInstalledSkills()
        }) { vm in
            SkillInstallView(viewModel: vm)
                // .environment() injects SkillManager into the sheet's view tree
                // Sheets create a new view hierarchy, so environment must be re-injected
                .environment(skillManager)
        }
    }

    // MARK: - Category Tabs

    /// Category tabs bar for leaderboard filtering
    ///
    /// Displays horizontal tabs: All Time / Trending (24h) / Hot
    /// Selected tab has a highlighted background; clicking switches the leaderboard content.
    /// CaseIterable allows iterating through all enum cases with ForEach.
    private var categoryTabs: some View {
        HStack(spacing: 4) {
            ForEach(SkillRegistryService.LeaderboardCategory.allCases) { category in
                Button {
                    Task { await viewModel.selectCategory(category) }
                } label: {
                    // Label combines icon (SF Symbol) and text
                    Label(category.displayName, systemImage: category.iconName)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            // Highlight selected tab with accent color at low opacity
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    viewModel.selectedCategory == category
                                        ? Color.accentColor.opacity(0.12)
                                        : Color.clear
                                )
                        )
                }
                // .plain removes default button chrome (border, press effect)
                .buttonStyle(.plain)
            }
            Spacer()

            // Show loading indicator inline when refreshing with existing data
            if viewModel.isLoading && !viewModel.displayedSkills.isEmpty {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Loading View

    /// Centered loading spinner shown during initial data fetch
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading registry...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Skill List

    /// Scrollable list of registry skills with selection support
    ///
    /// Uses SwiftUI List with selection binding (same pattern as DashboardView).
    /// When a skill is clicked, selectedSkillID is set → detail pane shows RegistrySkillDetailView.
    /// The `selection:` parameter enables single-selection mode in the List.
    private var skillList: some View {
        List(viewModel.displayedSkills, selection: $viewModel.selectedSkillID) { skill in
            RegistrySkillRowView(
                skill: skill,
                isInstalled: viewModel.isInstalled(skill),
                onInstall: { viewModel.installSkill(skill) }
            )
            // .tag associates this row with a selection value (the skill's id)
            // When user clicks this row, selectedSkillID is set to skill.id
            .tag(skill.id)
        }
        // .inset style with alternating row backgrounds — standard macOS list look
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Empty State

    /// Empty state view — shown when no skills are available
    ///
    /// Different messages depending on context:
    /// - Leaderboard scraping failed → suggest using search
    /// - Search returned no results → show "no results" message
    /// - Generic empty → fallback message
    ///
    /// @ViewBuilder allows returning different View types from if/else branches.
    /// Without @ViewBuilder, the return type must be a single concrete View type.
    @ViewBuilder
    private var emptyState: some View {
        if viewModel.leaderboardUnavailable {
            // Leaderboard parsing failed; suggest search as alternative
            EmptyStateView(
                icon: "magnifyingglass",
                title: "Leaderboard Unavailable",
                subtitle: "Use the search bar above to find skills on skills.sh"
            )
        } else if viewModel.isSearchActive {
            // Search returned no results
            EmptyStateView(
                icon: "magnifyingglass",
                title: "No Results",
                subtitle: "No skills match \"\(viewModel.searchText)\""
            )
        } else if let errorMessage = viewModel.errorMessage {
            // Generic error state
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                Text("Something went wrong")
                    .font(.title3)
                    .fontWeight(.medium)
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Generic empty state (shouldn't normally appear)
            EmptyStateView(
                icon: "tray",
                title: "No Skills",
                subtitle: "Unable to load skills from the registry"
            )
        }
    }
}
