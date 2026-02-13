import Foundation

/// SkillEditorViewModel manages the SKILL.md editor state (F05)
///
/// The editor provides two editing modes:
/// 1. Form mode: edit individual fields of YAML frontmatter
/// 2. Markdown mode: edit body content with live preview
@MainActor
@Observable
final class SkillEditorViewModel {

    let skillManager: SkillManager

    // MARK: - Form Fields (correspond to YAML frontmatter)

    var name: String = ""
    var description: String = ""
    var license: String = ""
    var author: String = ""
    var version: String = ""
    var allowedTools: String = ""

    // MARK: - Markdown Body

    var markdownBody: String = ""

    // MARK: - UI State

    var isSaving = false
    var saveError: String?
    var saveSuccess = false

    /// ID of the currently editing skill
    private var editingSkillID: String?

    init(skillManager: SkillManager) {
        self.skillManager = skillManager
    }

    /// Load skill data into the editor
    /// Extracts fields from Skill model and fills them into the editor form
    func load(skill: Skill) {
        editingSkillID = skill.id
        name = skill.metadata.name
        description = skill.metadata.description
        license = skill.metadata.license ?? ""
        author = skill.metadata.author ?? ""
        version = skill.metadata.version ?? ""
        allowedTools = skill.metadata.allowedTools ?? ""
        markdownBody = skill.markdownBody
        saveError = nil
        saveSuccess = false
    }

    /// Save edited content
    func save() async {
        guard let skillID = editingSkillID,
              let skill = skillManager.skills.first(where: { $0.id == skillID }) else {
            saveError = "Skill not found"
            return
        }

        isSaving = true
        saveError = nil

        // Build updated metadata
        let metadataExtra: SkillMetadata.MetadataExtra?
        if !author.isEmpty || !version.isEmpty {
            metadataExtra = SkillMetadata.MetadataExtra(
                author: author.isEmpty ? nil : author,
                version: version.isEmpty ? nil : version
            )
        } else {
            metadataExtra = nil
        }

        let updatedMetadata = SkillMetadata(
            name: name,
            description: description,
            license: license.isEmpty ? nil : license,
            metadata: metadataExtra,
            allowedTools: allowedTools.isEmpty ? nil : allowedTools
        )

        do {
            try await skillManager.saveSkill(skill, metadata: updatedMetadata, markdownBody: markdownBody)
            saveSuccess = true
            // Clear success message after 2 seconds
            // Task.sleep is similar to Go's time.Sleep but non-blocking
            try? await Task.sleep(for: .seconds(2))
            saveSuccess = false
        } catch {
            saveError = error.localizedDescription
        }

        isSaving = false
    }

    /// Check if there are unsaved changes
    func hasChanges(from skill: Skill) -> Bool {
        name != skill.metadata.name ||
        description != skill.metadata.description ||
        license != (skill.metadata.license ?? "") ||
        author != (skill.metadata.author ?? "") ||
        version != (skill.metadata.version ?? "") ||
        allowedTools != (skill.metadata.allowedTools ?? "") ||
        markdownBody != skill.markdownBody
    }
}
