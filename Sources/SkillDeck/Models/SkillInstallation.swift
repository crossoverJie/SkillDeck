import Foundation

/// SkillInstallation 记录某个 skill 在某个 Agent 下的安装状态
/// 一个 skill 可以通过 symlink 安装到多个 Agent
struct SkillInstallation: Identifiable, Hashable {
    let agentType: AgentType
    let path: URL              // skill 在该 Agent skills 目录下的路径
    let isSymlink: Bool        // 是否通过 symlink 链接（非原始文件）

    var id: String { "\(agentType.rawValue)-\(path.path)" }
}
