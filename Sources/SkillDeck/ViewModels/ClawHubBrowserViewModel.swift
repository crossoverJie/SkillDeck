import Foundation
import Observation

/// ClawHubBrowserViewModel owns all UI state for the dedicated ClawHub page.
///
/// This mirrors the role of `RegistryBrowserViewModel`, but keeps ClawHub-specific networking,
/// install rules, and installed-state matching isolated from the existing skills.sh flow.
@MainActor
@Observable
final class ClawHubBrowserViewModel {

    /// Small alert payload for install results and recoverable errors.
    ///
    /// Using an `Identifiable` value works well with `.alert(item:)`, because SwiftUI can present
    /// and dismiss the alert by simply toggling the optional between `nil` and a concrete value.
    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// Text currently entered in the toolbar search field.
    var searchText = ""

    /// Browse-list sort controls.
    ///
    /// These map directly to ClawHub's `/skills` query parameters and are only applied to the
    /// non-search listing, because the search endpoint currently uses a separate contract.
    var selectedSort: ClawHubService.SkillSort = .default
    var selectedDirection: ClawHubService.SortDirection = .descending
    var highlightedOnly = false
    var nonSuspiciousOnly = false

    /// Skills shown in the list pane.
    var displayedSkills: [ClawHubSkill] = []

    /// Whether the initial list or a search request is currently loading.
    var isLoading = false

    /// General list-level error message.
    var errorMessage: String?

    /// Selected list row ID for NavigationSplitView detail coordination.
    var selectedSkillID: String?

    /// Detailed metadata for the selected skill.
    var selectedSkillDetail: ClawHubSkillDetail?

    /// Parsed `SKILL.md` content for markdown rendering.
    var fetchedContent: SkillMDParser.ParseResult?

    /// Detail loading state is separate from content loading because either request can fail alone.
    var isLoadingDetail = false
    var isLoadingContent = false
    var detailError: String?
    var contentError: String?

    /// Whether an install request is currently running, tracked by slug so only the active row
    /// and detail button show a spinner / disabled state.
    var installingSkillSlug: String?

    /// Optional alert presented after installs or recoverable errors.
    var notice: Notice?

    /// We treat any non-empty search field as search mode.
    var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Convenience lookup for the selected list item.
    var selectedSkill: ClawHubSkill? {
        guard let selectedSkillID else { return nil }
        return displayedSkills.first { $0.id == selectedSkillID }
    }

    private let service: ClawHubService
    private let skillManager: SkillManager
    private var installedClawHubSlugs = Set<String>()
    private var installedSkillIDsNoSource = Set<String>()
    private var hasLoadedInitialSkills = false
    private var searchTask: Task<Void, Never>?
    private var currentDetailSlug: String?

    init(skillManager: SkillManager, service: ClawHubService = ClawHubService()) {
        self.skillManager = skillManager
        self.service = service
    }

    // MARK: - Lifecycle / list loading

    /// Initial page load.
    func onAppear() async {
        syncInstalledSkills()

        guard !hasLoadedInitialSkills else { return }
        hasLoadedInitialSkills = true
        await loadFeaturedSkills()
    }

    /// Refresh the currently visible list mode.
    func refresh() async {
        syncInstalledSkills()

        if isSearchActive {
            await performSearch(query: searchText)
        } else {
            await loadFeaturedSkills()
        }
    }

    /// Debounced search handler used by `.onChange(of: searchText)`.
    func onSearchTextChanged() {
        searchTask?.cancel()

        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            Task { await loadFeaturedSkills() }
            return
        }

        searchTask = Task {
            // Debounce prevents firing a network request on every keystroke.
            // This is similar to a frontend `setTimeout(..., 300)` search box pattern.
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(query: trimmedQuery)
        }
    }

    /// Update the browse sort chip selection.
    func selectSort(_ sort: ClawHubService.SkillSort) {
        guard selectedSort != sort else { return }
        selectedSort = sort
        reloadBrowseListIfNeeded()
    }

    /// Update ascending/descending ordering for the browse list.
    func selectDirection(_ direction: ClawHubService.SortDirection) {
        guard selectedDirection != direction else { return }
        selectedDirection = direction
        reloadBrowseListIfNeeded()
    }

    /// Toggle the `highlighted=true` filter used by the ClawHub website.
    func toggleHighlightedOnly() {
        highlightedOnly.toggle()
        reloadBrowseListIfNeeded()
    }

    /// Toggle the `nonSuspicious=true` filter used by the ClawHub website.
    func toggleNonSuspiciousOnly() {
        nonSuspiciousOnly.toggle()
        reloadBrowseListIfNeeded()
    }

    /// Refresh the installed badge cache from SkillManager's local skill list.
    func syncInstalledSkills() {
        installedClawHubSlugs = Set(
            skillManager.skills.compactMap { skill in
                guard skill.lockEntry?.sourceType == "clawhub" else { return nil }
                return skill.lockEntry?.source
            }
        )

        installedSkillIDsNoSource = Set(
            skillManager.skills.compactMap { skill in
                guard skill.lockEntry == nil else { return nil }
                return skill.id
            }
        )
    }

    /// Determine whether a ClawHub skill is already installed locally.
    func isInstalled(_ skill: ClawHubSkill) -> Bool {
        if installedClawHubSlugs.contains(skill.slug) {
            return true
        }

        return installedSkillIDsNoSource.contains(skill.slug)
    }

    /// Whether a specific row/detail action should show install progress.
    func isInstalling(_ skill: ClawHubSkill) -> Bool {
        installingSkillSlug == skill.slug
    }

    // MARK: - Detail loading

    /// Load both metadata and `SKILL.md` content for the selected skill.
    ///
    /// The stale-result guards are important: SwiftUI can keep a previous async task alive for a
    /// short time while the user clicks another row, so we only apply results if the same slug is
    /// still selected when the request finishes.
    func loadSelection(for skill: ClawHubSkill) async {
        currentDetailSlug = skill.slug
        selectedSkillDetail = nil
        fetchedContent = nil
        detailError = nil
        contentError = nil
        isLoadingDetail = true
        isLoadingContent = true

        let targetSlug = skill.slug

        do {
            let detail = try await service.fetchSkillDetail(slug: targetSlug)
            guard currentDetailSlug == targetSlug else { return }
            selectedSkillDetail = detail
        } catch {
            guard currentDetailSlug == targetSlug else { return }
            detailError = error.localizedDescription
        }
        isLoadingDetail = false

        do {
            let rawContent = try await service.fetchSkillContent(slug: targetSlug)
            guard currentDetailSlug == targetSlug else { return }

            do {
                fetchedContent = try SkillMDParser.parse(content: rawContent)
            } catch {
                // ClawHub skills are expected to use SKILL.md frontmatter, but we still keep a
                // markdown-only fallback so users can read imperfect community packages.
                fetchedContent = SkillMDParser.ParseResult(
                    metadata: SkillMetadata(name: skill.name, description: skill.descriptionText),
                    markdownBody: rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        } catch {
            guard currentDetailSlug == targetSlug else { return }
            contentError = error.localizedDescription
        }
        isLoadingContent = false
    }

    // MARK: - Installation

    /// Install a ClawHub skill into SkillDeck's canonical directory and symlink it to OpenClaw.
    func installSkill(_ skill: ClawHubSkill) {
        guard installingSkillSlug == nil else { return }

        Task {
            await performInstall(skill)
        }
    }

    private func performInstall(_ skill: ClawHubSkill) async {
        installingSkillSlug = skill.slug
        defer { installingSkillSlug = nil }

        do {
            let detail = try await service.fetchSkillDetail(slug: skill.slug)
            guard let version = detail.installVersion else {
                throw SkillManager.ImportError.parseFailed("ClawHub did not provide a version for \(skill.slug).")
            }

            var archiveData: Data?
            var archiveDownloadError: Error?
            do {
                archiveData = try await service.downloadSkillArchive(slug: skill.slug, version: version)
            } catch {
                archiveDownloadError = error
            }

            var skillContent: String?
            var skillContentError: Error?
            do {
                skillContent = try await service.fetchSkillContent(slug: skill.slug)
            } catch {
                skillContentError = error
            }

            if archiveData == nil && skillContent == nil {
                throw archiveDownloadError ?? skillContentError ?? ClawHubService.ServiceError.archiveUnavailable
            }

            let result = try await skillManager.installClawHubSkill(
                slug: skill.slug,
                version: version,
                detailPageURL: skill.browserURL.absoluteString,
                skillContent: skillContent,
                archiveData: archiveData,
                targetAgents: [.openClaw]
            )

            syncInstalledSkills()

            if result == .installedSkillMarkdownOnly {
                let reason = archiveDownloadError?.localizedDescription ?? "ClawHub did not return a downloadable archive for this skill version."
                notice = Notice(
                    title: "Installed with limited files",
                    message: "SkillDeck installed the SKILL.md file for OpenClaw, but auxiliary files were not included. Reason: \(reason)"
                )
            } else {
                notice = Notice(
                    title: "Installed",
                    message: "\(skill.name) is now available to OpenClaw."
                )
            }
        } catch {
            notice = Notice(title: "Installation Failed", message: error.localizedDescription)
        }
    }

    // MARK: - Private helpers

    private func loadFeaturedSkills() async {
        isLoading = true
        errorMessage = nil

        do {
            let skills = try await service.fetchSkills(options: browseOptions)
            displayedSkills = skills
            updateSelection(afterLoading: skills)
        } catch {
            displayedSkills = []
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func performSearch(query: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let skills = try await service.searchSkills(query: query)
            displayedSkills = skills
            selectedSkillID = skills.first?.id
        } catch {
            displayedSkills = []
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private var browseOptions: ClawHubService.BrowseOptions {
        ClawHubService.BrowseOptions(
            sort: selectedSort,
            direction: selectedDirection,
            highlightedOnly: highlightedOnly,
            nonSuspiciousOnly: nonSuspiciousOnly
        )
    }

    /// Only the browse list supports sort/filter query parameters, so changing those controls while
    /// search is active should not fire extra requests.
    private func reloadBrowseListIfNeeded() {
        guard !isSearchActive else { return }
        Task { await loadFeaturedSkills() }
    }

    /// Preserve the current selection when the refreshed list still contains the same skill.
    private func updateSelection(afterLoading skills: [ClawHubSkill]) {
        if let selectedSkillID, skills.contains(where: { $0.id == selectedSkillID }) {
            return
        }
        selectedSkillID = skills.first?.id
    }
}
