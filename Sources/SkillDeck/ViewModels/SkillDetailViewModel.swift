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
}
