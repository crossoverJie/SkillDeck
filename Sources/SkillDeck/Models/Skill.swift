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

    /// F12: 是否有远程更新可用
    /// 当 checkForUpdate 检测到远程 tree hash 与本地不同时设为 true
    var hasUpdate: Bool = false

    /// F12: 远程最新 tree hash
    /// 用于 updateSkill 时知道要更新到哪个版本
    var remoteTreeHash: String?

    /// F12: 远程最新 commit hash
    /// 用于生成 GitHub compare URL 显示差异链接
    /// 注意：tree hash 标识文件夹内容快照，commit hash 标识一次提交。
    /// GitHub compare URL 需要 commit hash 才能正确跳转。
    var remoteCommitHash: String?

    /// F12: 本地 commit hash（从 CommitHashCache 读取）
    /// 用于在 UI 中显示 `abc1234 → def5678` 的 hash 对比，
    /// 以及生成 GitHub compare URL `compare/<local>...<remote>`
    /// 老 skill（通过 npx skills 安装）在首次更新检查时通过 backfill 获取
    var localCommitHash: String?

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

/// Skill 更新检查的状态枚举
///
/// 用于在列表中显示每个 skill 的更新检查进度和结果。
/// 遵循 Equatable 协议（Swift 的值相等判断，类似 Java 的 equals），
/// 使 SwiftUI 能够对比状态变化来决定是否重新渲染视图。
enum SkillUpdateStatus: Equatable {
    /// 未检查（默认状态，不显示任何图标）
    case notChecked
    /// 正在检查中（显示旋转 spinner）
    case checking
    /// 有可用更新（显示橙色上箭头图标）
    case hasUpdate
    /// 已是最新版本（显示绿色勾选图标）
    case upToDate
    /// 检查失败（显示黄色警告图标，hover 显示错误信息）
    /// 关联值（associated value）类似 Rust 的 enum variant 携带数据，
    /// Java 中需要用子类或额外字段实现类似功能
    case error(String)
}
