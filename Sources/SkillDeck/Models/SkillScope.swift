import Foundation

/// SkillScope 表示 skill 的作用域
/// Swift enum 可以有关联值（associated values），这是 Java/Go enum 做不到的
/// 类似 Rust 的 enum / Go 的 tagged union
enum SkillScope: Hashable, Identifiable {
    /// 共享全局：位于 ~/.agents/skills/，可被所有 Agent 通过 symlink 引用
    case sharedGlobal

    /// Agent 本地：仅存在于某个 Agent 的 skills 目录（非 symlink）
    case agentLocal(AgentType)

    /// 项目级：位于项目目录的 .agents/skills/ 或 .claude/skills/
    case project(URL)

    var id: String {
        switch self {
        case .sharedGlobal: "global"
        case .agentLocal(let agent): "local-\(agent.rawValue)"
        case .project(let url): "project-\(url.path)"
        }
    }

    var displayName: String {
        switch self {
        case .sharedGlobal: "Global"
        case .agentLocal(let agent): "\(agent.displayName) Local"
        case .project: "Project"
        }
    }

    /// UI 徽章颜色
    var badgeColor: String {
        switch self {
        case .sharedGlobal: "blue"
        case .agentLocal: "gray"
        case .project: "green"
        }
    }
}
