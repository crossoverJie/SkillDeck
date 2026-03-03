import SwiftUI

/// Constants centralizes management of the app's global constants
/// Uses enum as a namespace because enums without cases cannot be instantiated
/// This is Swift's best practice for creating pure namespaces (similar to Java's private constructor + static fields)
enum Constants {

    /// Agent brand colors at the app level
    /// SwiftUI's Color is similar to Android's Color or CSS's color
    enum AgentColors {
        static func color(for agent: AgentType) -> Color {
            switch agent {
            case .claudeCode: Color(red: 0.91, green: 0.45, blue: 0.29)   // Coral #E8734A
            case .codex:      Color(red: 0.20, green: 0.78, blue: 0.35)   // Green
            case .geminiCLI:  Color(red: 0.26, green: 0.52, blue: 0.96)   // Blue
            case .copilotCLI: Color(red: 0.58, green: 0.34, blue: 0.92)   // Purple
            case .openCode:   Color(red: 0.0, green: 0.71, blue: 0.67)    // Teal #00B5AB
            case .antigravity: Color(red: 0.36, green: 0.42, blue: 0.75)  // Indigo #5C6BC0
            case .cursor:      Color(red: 0.06, green: 0.73, blue: 0.89)  // Cyan #10BAE3
            case .kiro:        Color(red: 0.55, green: 0.24, blue: 0.85)  // Violet
            case .codeBuddy:   Color(red: 0.91, green: 0.30, blue: 0.60)  // Pink #E84D99
            case .openClaw:    Color(red: 0.85, green: 0.18, blue: 0.15)  // Red #D92E26 (lobster/crayfish theme)
            case .trae:        Color(red: 0.20, green: 0.94, blue: 0.55)  // Bright Green #32F08C
            }
        }
    }

    /// Scope badge colors
    enum ScopeColors {
        static func color(for scope: SkillScope) -> Color {
            switch scope {
            case .sharedGlobal: .blue
            case .agentLocal:   .secondary
            case .project:      .green
            }
        }
    }

    /// Shared skills directory path
    static let sharedSkillsPath = "~/.agents/skills"

    /// Lock file path
    static let lockFilePath = "~/.agents/.skill-lock.json"

    /// Directory where custom repositories are cloned: ~/.agents/repos/
    static let reposBasePath = "~/.agents/repos"

    /// Config file that stores the list of user-configured custom repositories
    static let skillReposConfigPath = "~/.agents/.skilldeck-repos.json"
}
