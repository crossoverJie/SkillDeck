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

    /// Display-friendly path of the parent directory where this installation resides.
    /// Derives from the actual `path` property (e.g., ~/.agents/skills/foo → "~/.agents/skills"),
    /// ensuring correct display regardless of agent type changes.
    /// NSString.abbreviatingWithTildeInPath replaces the home directory prefix with ~
    var parentDirectoryDisplayPath: String {
        let parent = path.deletingLastPathComponent().path
        return NSString(string: parent).abbreviatingWithTildeInPath
    }

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
