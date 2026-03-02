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

    /// Dictionary mapping installed skill ID → source repo (owner/repo) from lock file.
    /// Used for source-aware "Installed" badge matching so that two registry skills
    /// with the same skillId but from different repos are distinguished correctly.
    /// Only populated for skills that have a lock entry with a `source` field.
    private var installedSkillSources: [String: String] = [:]

    /// Set of skill IDs installed without source tracking (no lock entry).
    /// Falls back to skillId-only matching for backward compatibility with
    /// manually installed skills that were not installed via the registry flow.
    private var installedSkillIDsNoSource: Set<String> = []

    /// Install sheet ViewModel (non-nil triggers sheet display)
    ///
    /// Uses `.sheet(item:)` binding pattern established by SkillInstallView:
    /// - When installVM is non-nil → sheet appears
    /// - When installVM is nil → sheet is dismissed
    /// This avoids the dual state synchronization timing issues of `.sheet(isPresented:)`
    var installVM: SkillInstallViewModel?

    // MARK: - Skill Content State

    /// Parsed SKILL.md content for the currently selected registry skill
    ///
    /// Non-nil when content has been successfully fetched and parsed.
    /// Contains both metadata (author, version, license) and the markdown body.
    /// Reset to nil when a different skill is selected (before new content loads).
    var fetchedContent: SkillMDParser.ParseResult?

    /// Whether SKILL.md content is currently being fetched for the selected skill
    ///
    /// Drives a ProgressView spinner in the detail view while content loads asynchronously.
    var isLoadingContent = false

    /// Error message when SKILL.md content fetch fails (nil means no error)
    ///
    /// Shown in the detail view with a fallback "View on skills.sh" link.
    /// Common causes: SKILL.md not found in repo, network timeout, non-UTF-8 encoding.
    var contentError: String?

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

    /// Content fetcher for downloading SKILL.md from GitHub raw URLs
    ///
    /// Uses the actor pattern for thread-safe caching, consistent with registryService.
    /// Fetches from `raw.githubusercontent.com` with main→master branch fallback.
    private let contentFetcher = SkillContentFetcher()

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

    /// Sync installed skill data from SkillManager for source-aware "Installed" badge matching.
    ///
    /// Builds two data structures:
    /// - `installedSkillSources`: maps skillId → source repo for skills with lock entries
    /// - `installedSkillIDsNoSource`: collects skillIds that have no lock entry (manual installs)
    ///
    /// This ensures that two registry skills sharing the same skillId but from different
    /// repositories are NOT both marked as "Installed" — only the one whose source matches
    /// the locally installed skill's lock entry will show the badge.
    func syncInstalledSkills() {
        var sources: [String: String] = [:]
        var noSource: Set<String> = []
        for skill in skillManager.skills {
            // If the skill has a lock entry with a source field (e.g., "owner/repo"),
            // record it for exact source matching.
            if let source = skill.lockEntry?.source {
                sources[skill.id] = source
            } else {
                // No lock entry means manually installed (not from registry).
                // Fall back to skillId-only matching for backward compatibility.
                noSource.insert(skill.id)
            }
        }
        installedSkillSources = sources
        installedSkillIDsNoSource = noSource
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
    /// Performs source-aware matching to avoid false positives when multiple registry skills
    /// share the same skillId but come from different repositories:
    ///
    /// 1. If a locally installed skill has the same skillId AND a matching source repo
    ///    (from its lock entry), return true — exact match.
    /// 2. If a locally installed skill has the same skillId but NO lock entry (manual install),
    ///    fall back to skillId-only matching for backward compatibility.
    /// 3. Otherwise return false — the skill is not installed.
    func isInstalled(_ registrySkill: RegistrySkill) -> Bool {
        // Check if installed with matching source repo (exact match on both skillId and source)
        if let installedSource = installedSkillSources[registrySkill.skillId] {
            return installedSource == registrySkill.source
        }
        // Fallback: skill installed without source tracking — match by ID only
        return installedSkillIDsNoSource.contains(registrySkill.skillId)
    }

    // MARK: - Skill Content Loading

    /// Load the full SKILL.md content for a registry skill from GitHub
    ///
    /// Called from the detail view's `.task(id:)` modifier — auto-cancels when the user
    /// selects a different skill. This prevents stale content from appearing.
    ///
    /// Flow:
    /// 1. Reset state (clear previous content/error, show loading spinner)
    /// 2. Fetch raw SKILL.md from GitHub via `SkillContentFetcher`
    /// 3. Parse with `SkillMDParser.parse(content:)` to extract metadata + markdown body
    /// 4. Guard against stale updates: only apply if the selected skill hasn't changed
    ///
    /// **Fallback for SKILL.md without frontmatter**: If the content doesn't have YAML frontmatter
    /// (no `---` delimiters), we treat the entire content as the markdown body with empty metadata.
    ///
    /// - Parameter skill: The registry skill whose SKILL.md to fetch
    func loadSkillContent(for skill: RegistrySkill) async {
        // Reset state for new content load
        fetchedContent = nil
        contentError = nil
        isLoadingContent = true

        // Capture the skill ID to guard against stale updates.
        // If the user clicks a different skill while this fetch is in-flight,
        // `selectedSkillID` will change. We check it after the await to discard stale results.
        let targetSkillID = skill.id

        do {
            // Fetch raw SKILL.md content from GitHub
            // SkillContentFetcher tries main branch first, then master, with 10-min cache
            let rawContent = try await contentFetcher.fetchContent(
                source: skill.source,
                skillId: skill.skillId
            )

            // Guard: discard result if user selected a different skill while we were fetching.
            // This is the Swift async equivalent of checking "is this still the current request?"
            // similar to checking a request ID in React's useEffect cleanup.
            guard selectedSkillID == targetSkillID else { return }

            // Parse the SKILL.md content into metadata + markdown body
            do {
                let result = try SkillMDParser.parse(content: rawContent)
                fetchedContent = result
            } catch {
                // Fallback: if parsing fails (e.g., no YAML frontmatter),
                // treat the entire content as the markdown body.
                // Create a minimal metadata with the skill name from the registry.
                let fallbackMetadata = SkillMetadata(
                    name: skill.name,
                    description: ""
                )
                fetchedContent = SkillMDParser.ParseResult(
                    metadata: fallbackMetadata,
                    markdownBody: rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        } catch {
            // Guard: discard error if user selected a different skill
            guard selectedSkillID == targetSkillID else { return }
            contentError = error.localizedDescription
        }

        isLoadingContent = false
    }
}
