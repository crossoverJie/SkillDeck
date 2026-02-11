import Foundation

/// SkillEditorViewModel 管理 SKILL.md 编辑器的状态（F05）
///
/// 编辑器提供两种编辑模式：
/// 1. 表单模式：编辑 YAML frontmatter 的各个字段
/// 2. Markdown 模式：编辑正文内容，带实时预览
@MainActor
@Observable
final class SkillEditorViewModel {

    let skillManager: SkillManager

    // MARK: - 表单字段（对应 YAML frontmatter）

    var name: String = ""
    var description: String = ""
    var license: String = ""
    var author: String = ""
    var version: String = ""
    var allowedTools: String = ""

    // MARK: - Markdown 正文

    var markdownBody: String = ""

    // MARK: - UI 状态

    var isSaving = false
    var saveError: String?
    var saveSuccess = false

    /// 当前编辑的 skill ID
    private var editingSkillID: String?

    init(skillManager: SkillManager) {
        self.skillManager = skillManager
    }

    /// 加载 skill 数据到编辑器
    /// 从 Skill 模型中提取各字段填充到编辑器表单
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

    /// 保存编辑内容
    func save() async {
        guard let skillID = editingSkillID,
              let skill = skillManager.skills.first(where: { $0.id == skillID }) else {
            saveError = "Skill not found"
            return
        }

        isSaving = true
        saveError = nil

        // 构建更新后的 metadata
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
            // 2 秒后清除成功提示
            // Task.sleep 类似 Go 的 time.Sleep，但不阻塞线程
            try? await Task.sleep(for: .seconds(2))
            saveSuccess = false
        } catch {
            saveError = error.localizedDescription
        }

        isSaving = false
    }

    /// 检查是否有未保存的修改
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
