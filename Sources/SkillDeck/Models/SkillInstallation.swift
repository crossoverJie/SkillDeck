import Foundation

/// SkillInstallation 记录某个 skill 在某个 Agent 下的安装状态
/// 一个 skill 可以通过 symlink 安装到多个 Agent
///
/// 安装分两种：
/// - 直接安装（isInherited == false）：skill 存在于该 Agent 自身的 skills 目录
/// - 继承安装（isInherited == true）：skill 存在于其他 Agent 的目录，但该 Agent 也能读取
///   例如 Copilot CLI 能读取 ~/.claude/skills/，所以 Claude Code 的 skill 对 Copilot 也可用
struct SkillInstallation: Identifiable, Hashable {
    let agentType: AgentType
    let path: URL              // skill 在该 Agent skills 目录下的路径
    let isSymlink: Bool        // 是否通过 symlink 链接（非原始文件）
    /// 是否为继承安装（来自其他 Agent 的目录，而非该 Agent 自身目录）
    /// 继承安装在 UI 中显示为只读状态，不可 toggle 操作
    let isInherited: Bool
    /// 继承来源 Agent（如 .claudeCode），仅当 isInherited == true 时有值
    /// 用于 UI 显示 "via Claude Code" 等提示文字
    let inheritedFrom: AgentType?

    var id: String { "\(agentType.rawValue)-\(path.path)" }

    /// 便捷初始化器：创建直接安装（非继承），保持向后兼容
    /// Swift 的 struct 默认会生成包含所有属性的 memberwise init（类似 Kotlin data class），
    /// 但添加自定义 init 后默认的仍然保留（因为在 extension 外定义）
    init(agentType: AgentType, path: URL, isSymlink: Bool,
         isInherited: Bool = false, inheritedFrom: AgentType? = nil) {
        self.agentType = agentType
        self.path = path
        self.isSymlink = isSymlink
        self.isInherited = isInherited
        self.inheritedFrom = inheritedFrom
    }
}
