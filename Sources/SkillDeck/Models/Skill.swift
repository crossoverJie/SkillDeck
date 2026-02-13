import Foundation

/// Skill is the core data model of the application, representing an AI Agent skill
/// It aggregates information from the file system, SKILL.md, and lock file
///
/// Using @Observable requires class type, but here we use struct to maintain immutability,
/// The ViewModel layer will use @Observable class to manage state
struct Skill: Identifiable, Hashable {
    /// Unique identifier: skill directory name (e.g., "agent-notifier")
    let id: String

    /// Canonical path (real path after resolving symlink)
    /// e.g., ~/.agents/skills/agent-notifier/
    let canonicalURL: URL

    /// Metadata parsed from SKILL.md
    var metadata: SkillMetadata

    /// Markdown body after frontmatter in SKILL.md
    var markdownBody: String

    /// Scope: Global shared / Agent local / Project level
    var scope: SkillScope

    /// Which Agents this skill is installed to (possibly via symlink)
    var installations: [SkillInstallation]

    /// Entry in lock file (can be nil, indicating not installed via package manager)
    var lockEntry: LockEntry?

    /// F12: Whether a remote update is available
    /// Set to true when checkForUpdate detects remote tree hash differs from local
    var hasUpdate: Bool = false

    /// F12: Remote latest tree hash
    /// Used to know which version to update to during updateSkill
    var remoteTreeHash: String?

    /// F12: Remote latest commit hash
    /// Used to generate GitHub compare URL to show diff links
    /// Note: tree hash identifies a folder content snapshot, commit hash identifies a commit.
    /// GitHub compare URL requires commit hash to jump correctly.
    var remoteCommitHash: String?

    /// F12: Local commit hash (read from CommitHashCache)
    /// Used to show hash comparison like abc1234 → def5678 in UI,
    /// And generate GitHub compare URL compare/<local>...<remote>
    /// Old skills (installed via npx skills) get this via backfill on first update check
    var localCommitHash: String?

    /// Full path of the SKILL.md file
    var skillMDURL: URL {
        canonicalURL.appendingPathComponent("SKILL.md")
    }

    /// Convenience property: display name (prefers metadata.name, otherwise uses directory name)
    var displayName: String {
        metadata.name.isEmpty ? id : metadata.name
    }

    /// Convenience property: which Agents this skill is installed to
    var installedAgents: [AgentType] {
        installations.map(\.agentType)
    }

    // Hashable implementation: equality check using id only (similar to Java's equals/hashCode)
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Skill, rhs: Skill) -> Bool {
        lhs.id == rhs.id
    }
}

/// Skill update check status enum
///
/// Used to show update check progress and result for each skill in the list.
/// Conforms to Equatable protocol (Swift value equality check, similar to Java's equals),
/// Allowing SwiftUI to compare state changes to decide whether to re-render the view.
enum SkillUpdateStatus: Equatable {
    /// Not checked (default state, shows no icon)
    case notChecked
    /// Checking (shows spinning spinner)
    case checking
    /// Update available (shows orange up arrow icon)
    case hasUpdate
    /// Up to date (shows green checkmark icon)
    case upToDate
    /// Check failed (shows yellow warning icon, hover shows error message)
    /// Associated values carry data similar to Rust's enum variants,
    /// Which requires subclasses or extra fields to implement in Java
    case error(String)
}
