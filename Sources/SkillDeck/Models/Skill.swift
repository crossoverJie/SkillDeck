import Foundation

/// Skill 是应用的核心数据模型，代表一个 AI Agent 技能
/// 它聚合了来自文件系统、SKILL.md 和 lock file 的所有信息
///
/// 使用 @Observable 需要 class 类型，但这里我们用 struct 保持不可变性，
/// ViewModel 层会用 @Observable class 来管理状态
struct Skill: Identifiable, Hashable {
    /// 唯一标识符：skill 目录名（如 "agent-notifier"）
    let id: String

    /// 规范路径（解析 symlink 后的真实路径）
    /// 例如 ~/.agents/skills/agent-notifier/
    let canonicalURL: URL

    /// SKILL.md 中解析出的元数据
    var metadata: SkillMetadata

    /// SKILL.md 中 frontmatter 之后的 markdown 正文
    var markdownBody: String

    /// 作用域：全局共享 / Agent 本地 / 项目级
    var scope: SkillScope

    /// 该 skill 安装到了哪些 Agent（可能通过 symlink）
    var installations: [SkillInstallation]

    /// lock file 中的条目（可能为 nil，表示未通过包管理器安装）
    var lockEntry: LockEntry?

    /// SKILL.md 文件的完整路径
    var skillMDURL: URL {
        canonicalURL.appendingPathComponent("SKILL.md")
    }

    /// 便捷属性：显示名称（优先用 metadata.name，否则用目录名）
    var displayName: String {
        metadata.name.isEmpty ? id : metadata.name
    }

    /// 便捷属性：该 skill 安装到了哪些 Agent
    var installedAgents: [AgentType] {
        installations.map(\.agentType)
    }

    // Hashable 实现：只用 id 判断相等（类似 Java 的 equals/hashCode）
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Skill, rhs: Skill) -> Bool {
        lhs.id == rhs.id
    }
}
