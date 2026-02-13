import Foundation

/// SkillScope represents the scope of a skill
/// Swift enums can have associated values, which Java/Go enums cannot do
/// Similar to Rust enum / Go tagged union
enum SkillScope: Hashable, Identifiable {
    /// Shared global: located in ~/.agents/skills/, can be referenced by all Agents via symlink
    case sharedGlobal

    /// Agent local: only exists in a specific Agent's skills directory (not symlink)
    case agentLocal(AgentType)

    /// Project level: located in project directory .agents/skills/ or .claude/skills/
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

    /// UI badge color
    var badgeColor: String {
        switch self {
        case .sharedGlobal: "blue"
        case .agentLocal: "gray"
        case .project: "green"
        }
    }
}
