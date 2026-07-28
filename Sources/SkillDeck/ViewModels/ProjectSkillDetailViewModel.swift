import Observation

/// ProjectSkillDetailViewModel keeps update state isolated per project skill.
/// Unlike SkillDetailViewModel, it never reads or writes the user's global skill metadata.
@MainActor
@Observable
final class ProjectSkillDetailViewModel {
    let service: ProjectSkillUpdateService
    let row: ProjectSkillRow
    var skill: Skill?
    var isLoading = false
    var isLinking = false
    var isChecking = false
    var isUpdating = false
    var repositoryInput = ""
    var remoteHash: String?
    var hasUpdate = false
    var errorMessage: String?
    /// A successful operation needs persistent visible feedback; project updates previously only
    /// changed button state, which made a completed check indistinguishable from no action.
    var statusMessage: String?

    init(row: ProjectSkillRow) {
        self.row = row
        self.service = ProjectSkillUpdateService(sourceRoot: row.sourceURL.deletingLastPathComponent())
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            skill = try await service.loadSkill(named: row.name, at: row.sourceURL)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func linkRepository() async {
        guard let skill else { return }
        let input = repositoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        isLinking = true
        defer { isLinking = false }
        do {
            self.skill = try await service.link(skill: skill, repositoryInput: input)
            repositoryInput = ""
            remoteHash = nil
            hasUpdate = false
            errorMessage = nil
            statusMessage = L10n.currentString(L10nKeys.projectDetailLinkedAndSynced)
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    func checkForUpdate() async {
        guard let skill else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let result = try await service.checkForUpdate(skill: skill)
            remoteHash = result.remoteHash
            hasUpdate = result.hasUpdate
            errorMessage = nil
            statusMessage = L10n.currentString(result.hasUpdate ? L10nKeys.projectDetailUpdateAvailable : L10nKeys.projectDetailUpToDate)
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    func update() async {
        guard let skill, let remoteHash else { return }
        isUpdating = true
        defer { isUpdating = false }
        do {
            self.skill = try await service.update(skill: skill, remoteHash: remoteHash)
            self.remoteHash = nil
            hasUpdate = false
            errorMessage = nil
            statusMessage = L10n.currentString(L10nKeys.projectDetailUpdated)
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }
}
