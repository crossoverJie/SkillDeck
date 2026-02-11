import Foundation

/// LockEntry 对应 .skill-lock.json 中每个 skill 的条目
/// Codable 让它可以直接从 JSON 反序列化
struct LockEntry: Codable, Equatable {
    var source: String           // e.g., "crossoverJie/skills"
    var sourceType: String       // e.g., "github"
    var sourceUrl: String        // e.g., "https://github.com/crossoverJie/skills.git"
    var skillPath: String        // e.g., "skills/agent-notifier/SKILL.md"
    var skillFolderHash: String  // Git hash，用于检测更新
    var installedAt: String      // ISO 8601 时间戳
    var updatedAt: String        // ISO 8601 时间戳
}

/// LockFile 对应整个 .skill-lock.json 文件结构
struct LockFile: Codable {
    var version: Int
    var skills: [String: LockEntry]
    var dismissed: [String: Bool]?
    var lastSelectedAgents: [String]?
}
