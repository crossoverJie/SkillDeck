import Foundation
import AppKit

/// SkillDetailViewModel 管理 Skill 详情页的状态
@MainActor
@Observable
final class SkillDetailViewModel {

    let skillManager: SkillManager

    /// 是否显示编辑器
    var isEditing = false

    /// 操作反馈消息
    var feedbackMessage: String?

    /// F12: 是否正在检查更新
    var isCheckingUpdate = false

    /// F12: 是否正在执行更新
    var isUpdating = false

    /// F12: 更新操作的错误信息
    var updateError: String?

    /// F12: 检查结果 —— 是否为最新（用于显示 "Up to Date" 提示）
    var showUpToDate = false

    // MARK: - Link to Repository State（手动关联仓库状态）

    /// 用户输入的仓库地址（支持 "owner/repo" 或完整 URL）
    var repoURLInput = ""

    /// 是否正在执行关联操作（shallow clone + 扫描 + 写缓存）
    var isLinking = false

    /// 关联操作的错误信息
    var linkError: String?

    init(skillManager: SkillManager) {
        self.skillManager = skillManager
    }

    /// 获取指定 skill 的最新数据
    /// 因为 skills 可能被外部修改，每次都从 SkillManager 获取最新版本
    func skill(id: String) -> Skill? {
        skillManager.skills.first { $0.id == id }
    }

    /// 切换 Agent 分配状态
    func toggleAgent(_ agentType: AgentType, for skill: Skill) async {
        do {
            try await skillManager.toggleAssignment(skill, agent: agentType)
            feedbackMessage = nil
        } catch {
            feedbackMessage = error.localizedDescription
        }
    }

    /// 在 Finder 中显示 skill 目录
    /// NSWorkspace 是 macOS AppKit 框架提供的系统交互类
    func revealInFinder(skill: Skill) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: skill.canonicalURL.path)
    }

    /// 在 Terminal 中打开 skill 目录
    func openInTerminal(skill: Skill) {
        let url = skill.canonicalURL
        // AppleScript 是 macOS 的自动化脚本语言，这里用它来打开 Terminal
        let script = """
        tell application "Terminal"
            do script "cd '\(url.path)'"
            activate
        end tell
        """
        // NSAppleScript 执行 AppleScript 代码
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    // MARK: - F12: Update Check

    /// 检查单个 skill 是否有可用更新
    ///
    /// 调用 SkillManager.checkForUpdate，更新 UI 状态。
    /// 返回值包含 remoteCommitHash，用于生成 GitHub compare URL 显示差异链接。
    func checkForUpdate(skill: Skill) async {
        isCheckingUpdate = true
        updateError = nil
        showUpToDate = false

        do {
            let (hasUpdate, remoteHash, remoteCommitHash) = try await skillManager.checkForUpdate(skill: skill)

            // 更新 SkillManager 中对应 skill 的状态
            if let index = skillManager.skills.firstIndex(where: { $0.id == skill.id }) {
                skillManager.skills[index].hasUpdate = hasUpdate
                skillManager.skills[index].remoteTreeHash = remoteHash
                // 存储远程 commit hash，用于 UI 显示 hash 对比和 GitHub 链接
                skillManager.skills[index].remoteCommitHash = hasUpdate ? remoteCommitHash : nil
                skillManager.updateStatuses[skill.id] = hasUpdate

                // 更新本地 commit hash（checkForUpdate 中可能执行了 backfill）
                let cachedLocalHash = await skillManager.getCachedCommitHash(for: skill.id)
                skillManager.skills[index].localCommitHash = cachedLocalHash
            }

            if !hasUpdate {
                showUpToDate = true
                // 2 秒后自动隐藏 "Up to Date" 提示
                // Task.sleep 类似 Go 的 time.Sleep，但不阻塞线程
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    showUpToDate = false
                }
            }
        } catch {
            updateError = error.localizedDescription
        }

        isCheckingUpdate = false
    }

    /// 执行 skill 更新
    ///
    /// 从远程拉取最新文件覆盖本地，更新 lock entry
    func updateSkill(_ skill: Skill) async {
        guard let remoteHash = skill.remoteTreeHash else { return }

        isUpdating = true
        updateError = nil

        do {
            try await skillManager.updateSkill(skill, remoteHash: remoteHash)
        } catch {
            updateError = error.localizedDescription
        }

        isUpdating = false
    }

    // MARK: - Link to Repository

    /// 将 skill 手动关联到 GitHub 仓库
    ///
    /// 调用 SkillManager.linkSkillToRepository，完成后 refresh 会自动
    /// 从缓存合成 LockEntry，UI 会从 linkToRepoSection 切换到 lockFileSection。
    func linkToRepository(skill: Skill) async {
        let input = repoURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        isLinking = true
        linkError = nil

        do {
            try await skillManager.linkSkillToRepository(skill, repoInput: input)
            // 成功后清空输入（UI 会自动切换到 lockFileSection）
            repoURLInput = ""
        } catch {
            linkError = error.localizedDescription
        }

        isLinking = false
    }
}
