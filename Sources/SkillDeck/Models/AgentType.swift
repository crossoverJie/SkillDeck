import Foundation

/// AgentType represents supported AI code assistant types
/// Similar to Java enum, but Swift enum is more powerful, supporting associated values and methods
enum AgentType: String, CaseIterable, Identifiable, Codable {
    case claudeCode = "claude-code"
    case codex = "codex"
    case geminiCLI = "gemini-cli"
    case copilotCLI = "copilot-cli"
    case openCode = "opencode"       // OpenCode: Open source AI programming CLI tool
    case antigravity = "antigravity"   // Antigravity: Google's AI coding agent (https://antigravity.google)
    case cursor = "cursor"               // Cursor: AI-powered code editor (https://cursor.com)

    // Identifiable protocol requirement (similar to Java's Comparable), needed for SwiftUI list rendering
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .geminiCLI: "Gemini CLI"
        case .copilotCLI: "Copilot CLI"
        case .openCode: "OpenCode"
        case .antigravity: "Antigravity"
        case .cursor: "Cursor"
        }
    }

    /// Color scheme for each Agent, used for UI distinction
    /// SwiftUI uses Color type, similar to Android's Color
    var brandColor: String {
        switch self {
        case .claudeCode: "coral"     // #E8734A
        case .codex: "green"
        case .geminiCLI: "blue"
        case .copilotCLI: "purple"
        case .openCode: "teal"
        case .antigravity: "indigo"
        case .cursor: "cyan"
        }
    }

    /// SF Symbol icon name corresponding to the Agent
    /// SF Symbols is Apple's system icon library, similar to Material Icons
    var iconName: String {
        switch self {
        case .claudeCode: "brain.head.profile"
        case .codex: "terminal"
        case .geminiCLI: "sparkles"
        case .copilotCLI: "airplane"
        case .openCode: "chevron.left.forwardslash.chevron.right"  // </> Code symbol, fitting OpenCode's programming theme
        case .antigravity: "arrow.up.circle"  // Upward motion symbolizing anti-gravity
        case .cursor: "cursorarrow.rays"        // Cursor arrow icon matching the Cursor IDE brand
        }
    }

    /// User-level skills directory path for the Agent
    /// ~ represents user home directory, e.g., /Users/chenjie
    var skillsDirectoryPath: String {
        switch self {
        case .claudeCode: "~/.claude/skills"
        case .codex: "~/.agents/skills"     // Codex directly uses the shared directory
        case .geminiCLI: "~/.gemini/skills"
        case .copilotCLI: "~/.copilot/skills"
        case .openCode: "~/.config/opencode/skills"  // OpenCode uses XDG-style configuration path
        case .antigravity: "~/.gemini/antigravity/skills"  // Antigravity stores skills under Gemini's config directory
        case .cursor: "~/.cursor/skills"                    // Cursor IDE skills directory
        }
    }

    /// Resolved absolute path URL
    var skillsDirectoryURL: URL {
        let expanded = NSString(string: skillsDirectoryPath).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    /// Configuration directory of the Agent
    var configDirectoryPath: String? {
        switch self {
        case .claudeCode: "~/.claude"
        case .codex: nil                    // Codex does not have an independent configuration directory
        case .geminiCLI: "~/.gemini"
        case .copilotCLI: "~/.copilot"
        case .openCode: "~/.config/opencode"
        case .antigravity: "~/.gemini/antigravity"
        case .cursor: "~/.cursor"
        }
    }

    /// CLI command used to detect if the Agent is installed
    var detectCommand: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .geminiCLI: "gemini"
        case .copilotCLI: "gh"
        case .openCode: "opencode"
        case .antigravity: "antigravity"
        case .cursor: "cursor"
        }
    }

    /// Skills directories of other Agents that this Agent can read in addition to its own skills directory
    ///
    /// This is the "Single Source of Truth" for cross-directory reading rules:
    /// - Copilot CLI can read both ~/.copilot/skills/ and ~/.claude/skills/
    ///   (See GitHub official documentation: https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)
    /// - OpenCode can read both ~/.claude/skills/ and ~/.agents/skills/
    ///   (See: https://opencode.ai/docs/skills/#place-files)
    /// - Other Agents currently do not have cross-directory reading behavior
    ///
    /// Returns an array of tuples: (Directory URL, Source Agent Type)
    /// Similar to Java's Pair<URL, AgentType>, Swift uses named tuples for better clarity
    var additionalReadableSkillsDirectories: [(url: URL, sourceAgent: AgentType)] {
        switch self {
        case .copilotCLI:
            // Copilot CLI can also read Claude Code's skills directory
            return [(AgentType.claudeCode.skillsDirectoryURL, .claudeCode)]
        case .openCode:
            // OpenCode can also read Claude Code's and Codex's skills directories
            // See: https://opencode.ai/docs/skills/#place-files
            return [
                (AgentType.claudeCode.skillsDirectoryURL, .claudeCode),
                (AgentType.codex.skillsDirectoryURL, .codex)
            ]
        case .cursor:
            // Cursor can also read Claude Code's skills directory
            return [(AgentType.claudeCode.skillsDirectoryURL, .claudeCode)]
        default:
            return []
        }
    }
}
