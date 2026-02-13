import Foundation

/// SkillInstallation records the installation status of a skill under an Agent
/// A skill can be installed to multiple Agents via symlink
///
/// Two types of installation:
/// - Direct installation (isInherited == false): skill exists in the Agent's own skills directory
/// - Inherited installation (isInherited == true): skill exists in another Agent's directory, but this Agent can also read it
///   e.g. Copilot CLI can read ~/.claude/skills/, so Claude Code's skills are also available to Copilot
struct SkillInstallation: Identifiable, Hashable {
    let agentType: AgentType
    let path: URL              // Path of the skill in this Agent's skills directory
    let isSymlink: Bool        // Whether it is a symlink (not an original file)
    /// Whether it is an inherited installation (from another Agent's directory, not this Agent's own directory)
    /// Inherited installations are shown as read-only in UI, cannot be toggled
    let isInherited: Bool
    /// Source Agent of inheritance (e.g. .claudeCode), only has value when isInherited == true
    /// Used for UI display like "via Claude Code"
    let inheritedFrom: AgentType?

    var id: String { "\(agentType.rawValue)-\(path.path)" }

    /// Convenience initializer: create direct installation (non-inherited), keeping backward compatibility
    /// Swift structs generate memberwise init by default (similar to Kotlin data class),
    /// But adding custom init keeps the default one (because it's defined outside extension)
    init(agentType: AgentType, path: URL, isSymlink: Bool,
         isInherited: Bool = false, inheritedFrom: AgentType? = nil) {
        self.agentType = agentType
        self.path = path
        self.isSymlink = isSymlink
        self.isInherited = isInherited
        self.inheritedFrom = inheritedFrom
    }
}
