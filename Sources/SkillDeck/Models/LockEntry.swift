import Foundation

/// LockEntry corresponds to each skill entry in .skill-lock.json
/// Codable allows it to be deserialized directly from JSON
struct LockEntry: Codable, Equatable {
    var source: String           // e.g., "crossoverJie/skills"
    var sourceType: String       // e.g., "github"
    var sourceUrl: String        // e.g., "https://github.com/crossoverJie/skills.git"
    var skillPath: String        // e.g., "skills/agent-notifier/SKILL.md"
    var skillFolderHash: String  // Git hash, used for update detection
    var installedAt: String      // ISO 8601 timestamp
    var updatedAt: String        // ISO 8601 timestamp
}

/// LockFile corresponds to the entire .skill-lock.json file structure
struct LockFile: Codable {
    var version: Int
    var skills: [String: LockEntry]
    var dismissed: [String: Bool]?
    var lastSelectedAgents: [String]?
}
