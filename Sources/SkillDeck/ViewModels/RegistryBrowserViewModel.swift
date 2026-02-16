import Foundation

/// RegistryBrowserViewModel manages the state for the F09 Registry Browser feature
///
/// Handles three modes of operation:
/// 1. **Leaderboard browsing**: Displays skills from all-time / trending / hot categories
/// 2. **Search**: Searches skills.sh registry via API with debounce
/// 3. **Install**: Triggers install flow for a selected registry skill
///
/// @Observable is a macro (macOS 14+) that automatically tracks property changes
/// and triggers SwiftUI view updates — replaces the older ObservableObject + @Published pattern.
/// Similar to Vue.js reactive data or Android's LiveData.
///
/// @MainActor ensures all properties update on the main thread, which is required for UI state.
/// Similar to Android's @UiThread annotation — UI updates must happen on the main thread.
@MainActor
@Observable
final class RegistryBrowserViewModel {

    // MARK: - State

    /// Current leaderboard category tab (All Time / Trending / Hot)
    var selectedCategory: SkillRegistryService.LeaderboardCategory = .allTime

    /// Search text entered by user (empty = show leaderboard, non-empty = show search results)
    var searchText = ""

    /// Skills displayed in current view (either leaderboard or search results)
    var displayedSkills: [RegistrySkill] = []

    /// Whether data is currently loading (shows spinner in UI)
    var isLoading = false

    /// Error message to display (nil means no error)
    var errorMessage: String?

    /// Whether leaderboard scraping failed (triggers fallback UI suggesting search)
    /// Separate from errorMessage to allow different UI treatment
    var leaderboardUnavailable = false

    /// Set of locally installed skill IDs (for showing "Installed" badges)
    /// Uses Set for O(1) lookup — similar to Java's HashSet
    var installedSkillIDs: Set<String> = []

    /// Install sheet ViewModel (non-nil triggers sheet display)
    ///
    /// Uses `.sheet(item:)` binding pattern established by SkillInstallView:
    /// - When installVM is non-nil → sheet appears
    /// - When installVM is nil → sheet is dismissed
    /// This avoids the dual state synchronization timing issues of `.sheet(isPresented:)`
    var installVM: SkillInstallViewModel?

    /// Currently selected registry skill ID (drives the detail pane display)
    ///
    /// When user clicks a skill in the list, this is set to that skill's id,
    /// and the detail pane shows RegistrySkillDetailView.
    /// Similar to DashboardView's selectedSkillID binding pattern.
    var selectedSkillID: String?

    /// Convenience: get the currently selected RegistrySkill object
    ///
    /// Looks up the selected skill from displayedSkills by ID.
    /// Returns nil if no skill is selected or if the ID doesn't match any displayed skill.
    /// `first(where:)` is Swift's collection search (similar to Java Stream's findFirst + filter).
    var selectedSkill: RegistrySkill? {
        guard let id = selectedSkillID else { return nil }
        return displayedSkills.first { $0.id == id }
    }

    /// Whether search mode is active (controls which content to display)
    /// Computed property — no backing storage needed, derived from searchText
    var isSearchActive: Bool {
        !searchText.isEmpty
    }

    // MARK: - Dependencies

    /// Registry service for API calls and HTML scraping
    private let registryService = SkillRegistryService()

    /// SkillManager reference for checking installed skills and triggering installs
    private let skillManager: SkillManager

    // MARK: - Search Debounce

    /// Debounce task for search-as-you-type
    ///
    /// When user types quickly, we cancel the previous search task and create a new one.
    /// Only the last keystroke triggers an actual API call (after 300ms delay).
    /// Similar to RxJava's debounce() or JavaScript's lodash.debounce().
    ///
    /// Task<Void, Never> means: async task that returns nothing and never throws errors.
    /// The `Never` type parameter means errors are handled internally (try? catches them).
    private var searchTask: Task<Void, Never>?

    // MARK: - Init

    /// Initialize with SkillManager dependency
    ///
    /// SkillManager is injected from the view tree (passed down from ContentView).
    /// This follows the Dependency Injection pattern — ViewModel doesn't create its own SkillManager,
    /// it receives the shared instance, similar to Spring's @Autowired.
    init(skillManager: SkillManager) {
        self.skillManager = skillManager
    }

    // MARK: - Lifecycle

    /// Called when the view first appears (from SwiftUI's `.task` modifier)
    ///
    /// `.task` runs async code when the view first appears — similar to Android's onResume + coroutine
    /// or React's useEffect([], ...) with empty dependency array.
    func onAppear() async {
        syncInstalledSkills()
        await loadLeaderboard()
    }

    /// Sync the set of locally installed skill IDs from SkillManager
    ///
    /// Cross-references registry skills with locally installed skills to show "Installed" badges.
    /// Called on appear and after each install to keep badges up-to-date.
    func syncInstalledSkills() {
        installedSkillIDs = Set(skillManager.skills.map(\.id))
    }

    // MARK: - Leaderboard

    /// Load leaderboard data for the selected category
    ///
    /// Fetches skill data from skills.sh HTML page via SkillRegistryService.
    /// On failure, sets `leaderboardUnavailable` to show a fallback UI suggesting search.
    func loadLeaderboard() async {
        // Don't load leaderboard if user is searching
        guard !isSearchActive else { return }

        isLoading = true
        errorMessage = nil
        leaderboardUnavailable = false

        do {
            let skills = try await registryService.fetchLeaderboard(category: selectedCategory)
            displayedSkills = skills
        } catch {
            // Leaderboard scraping failed — degrade gracefully
            // Don't show a scary error; suggest using search instead
            errorMessage = "Unable to load leaderboard. Try searching instead."
            leaderboardUnavailable = true
            displayedSkills = []
        }

        isLoading = false
    }

    /// Switch leaderboard category tab and reload data
    ///
    /// Called when user clicks a category tab (All Time / Trending / Hot).
    /// The service has a 5-minute cache, so switching between tabs is fast
    /// after the initial load.
    func selectCategory(_ category: SkillRegistryService.LeaderboardCategory) async {
        selectedCategory = category
        await loadLeaderboard()
    }

    /// Refresh current data (clear cache and reload)
    ///
    /// Called from toolbar refresh button. Clears the service cache
    /// so fresh data is fetched from skills.sh.
    func refresh() async {
        await registryService.clearCache()
        if isSearchActive {
            await performSearch()
        } else {
            await loadLeaderboard()
        }
    }

    // MARK: - Search

    /// Called when searchText changes (with debounce)
    ///
    /// Implements search-as-you-type with a 300ms debounce:
    /// 1. Cancel any pending search task
    /// 2. If search text is empty, switch back to leaderboard
    /// 3. Otherwise, wait 300ms then perform search
    ///
    /// The debounce prevents excessive API calls while the user is typing quickly.
    /// `Task.sleep(for:)` suspends the task; if the task is cancelled (by a new keystroke),
    /// the sleep throws CancellationError which is caught by `try?`.
    func onSearchTextChanged() {
        // Cancel previous pending search
        searchTask?.cancel()

        if searchText.isEmpty {
            // User cleared the search field — switch back to leaderboard
            Task { await loadLeaderboard() }
            return
        }

        // Create new debounced search task
        searchTask = Task {
            // Wait 300ms for debounce — if user types another character,
            // this task gets cancelled and a new one starts
            try? await Task.sleep(for: .milliseconds(300))

            // Check if task was cancelled during the sleep (user typed more)
            // Task.isCancelled is a static property on the current task
            guard !Task.isCancelled else { return }

            await performSearch()
        }
    }

    /// Execute search against skills.sh API
    ///
    /// Private method called after debounce completes.
    /// Updates displayedSkills with search results or shows error.
    private func performSearch() async {
        guard !searchText.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        do {
            let skills = try await registryService.search(query: searchText)
            // Only update if we're still in search mode (user may have cleared search during request)
            if isSearchActive {
                displayedSkills = skills
            }
        } catch {
            if isSearchActive {
                errorMessage = "Search failed: \(error.localizedDescription)"
                displayedSkills = []
            }
        }

        isLoading = false
    }

    // MARK: - Install

    /// Initiate install flow for a registry skill
    ///
    /// Creates a SkillInstallViewModel pre-filled with the skill's source repository,
    /// then sets `autoFetch = true` so the install sheet automatically starts scanning
    /// when it appears (no need for user to click "Scan" manually).
    ///
    /// This reuses the existing F10 install flow (SkillInstallViewModel + SkillInstallView),
    /// which handles: clone repo → scan for SKILL.md → select skills/agents → install.
    ///
    /// - Parameter registrySkill: The registry skill to install
    func installSkill(_ registrySkill: RegistrySkill) {
        let vm = SkillInstallViewModel(skillManager: skillManager)
        // Pre-fill the repo URL input with the skill's source (e.g., "vercel-labs/agent-skills")
        vm.repoURLInput = registrySkill.source
        // Auto-trigger repository scanning when the sheet appears
        vm.autoFetch = true
        // Only pre-select the specific skill the user clicked, not all skills in the repo
        vm.targetSkillId = registrySkill.skillId
        installVM = vm
    }

    /// Check if a registry skill is already installed locally
    ///
    /// Compares the registry skill's skillId against locally installed skill IDs.
    /// Returns true if found — the UI will show an "Installed" badge and disable the install button.
    func isInstalled(_ registrySkill: RegistrySkill) -> Bool {
        installedSkillIDs.contains(registrySkill.skillId)
    }
}
