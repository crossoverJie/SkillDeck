import Foundation

/// AgentType represents supported AI code assistant types
/// Similar to Java enum, but Swift enum is more powerful, supporting associated values and methods
enum AgentType: String, CaseIterable, Identifiable, Codable, Sendable {
    // Declaration order IS the display order: `CaseIterable.allCases` drives the sidebar,
    // install sheets, import sheets and Agent toggles, so daily-driver agents come first and
    // rarely used / standalone agents are pushed to the bottom. Reorder here to reorder the UI.
    case claudeCode = "claude-code"
    case codex = "codex"
    case copilotCLI = "copilot-cli"
    case openCode = "opencode"       // OpenCode: Open source AI programming CLI tool
    case pi = "pi"                           // Pi: terminal coding agent (https://pi.dev)
    case cursor = "cursor"               // Cursor: AI-powered code editor (https://cursor.com)
    case kiro = "kiro"                     // Kiro: AWS AI IDE built on Code OSS (https://kiro.dev)
    case codeBuddy = "codebuddy"           // CodeBuddy: Tencent Cloud AI coding assistant (https://www.codebuddy.ai)
    case trae = "trae"                       // Trae: ByteDance's AI IDE (https://trae.ai)
    case qoder = "qoder"                     // Qoder: AI coding agent (https://qoder.ai)
    case qclaw = "qclaw"                     // QClaw: AI coding assistant (skills in ~/.qclaw/skills)
    case workbuddy = "workbuddy"             // WorkBuddy: AI coding assistant (skills in ~/.workbuddy/skills)
    // Bottom group: standalone or less frequently used agents.
    case geminiCLI = "gemini-cli"
    case antigravity = "antigravity"   // Antigravity: Google's AI coding agent (https://antigravity.google)
    case openClaw = "openclaw"             // OpenClaw: AI coding assistant with ClawHub registry (https://openclaw.ai)

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
        case .kiro: "Kiro"
        case .codeBuddy: "CodeBuddy"
        case .openClaw: "OpenClaw"
        case .trae: "Trae"
        case .qoder: "Qoder"
        case .qclaw: "QClaw"
        case .workbuddy: "WorkBuddy"
        case .pi: "Pi"
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
        case .kiro: "violet"
        case .codeBuddy: "pink"
        case .openClaw: "red"
        case .trae: "brightGreen"
        case .qoder: "orange"
        case .qclaw: "mint"
        case .workbuddy: "yellow"
        case .pi: "slate"
        }
    }

    /// SF Symbol fallback used when no bundled brand logo is available
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
        case .kiro: "k.circle"                   // Letter K icon for Kiro
        case .codeBuddy: "c.circle"               // Letter C icon for CodeBuddy
        case .openClaw: "o.circle"               // Letter O icon for OpenClaw
        case .trae: "t.circle"                     // Letter T icon for Trae
        case .qoder: "q.circle"                     // Letter Q icon for Qoder
        case .qclaw: "hand.raised.circle"            // Hand/claw icon for QClaw
        case .workbuddy: "w.circle"                 // Letter W icon for WorkBuddy
        case .pi: "p.circle"                        // Letter P icon for Pi
        }
    }

    /// Bundled brand logo file (SVG, no extension) in Resources/AgentIcons.
    /// Returns nil when no public logo exists (QClaw), letting the UI fall back to `iconName`.
    var iconResourceName: String? {
        switch self {
        case .claudeCode: "AgentClaudeCode"
        case .codex: "AgentCodex"
        case .geminiCLI: "AgentGeminiCLI"
        case .copilotCLI: "AgentCopilotCLI"
        case .openCode: "AgentOpenCode"
        case .antigravity: "AgentAntigravity"
        case .cursor: "AgentCursor"
        case .kiro: "AgentKiro"
        case .codeBuddy: "AgentCodeBuddy"
        case .openClaw: "AgentOpenClaw"
        case .trae: "AgentTrae"
        case .qoder: "AgentQoder"
        case .qclaw: nil
        case .workbuddy: "AgentWorkBuddy"
        case .pi: "AgentPi"
        }
    }

    /// Monochrome logos are drawn as template images so they follow the SwiftUI tint.
    var usesTemplateIcon: Bool {
        switch self {
        case .copilotCLI, .openCode, .cursor, .qoder, .pi: true
        default: false
        }
    }

    /// User-level skills directory path for the Agent
    /// ~ represents user home directory, e.g., /Users/chenjie
    var skillsDirectoryPath: String {
        switch self {
        case .claudeCode:
            return "~/.claude/skills"
        case .codex:
            return "~/.codex/skills"        // Codex-specific skills directory (also reads ~/.agents/skills/)
        case .geminiCLI:
            return "~/.gemini/skills"
        case .copilotCLI:
            return "~/.copilot/skills"
        case .openCode:
            return "~/.config/opencode/skills"  // OpenCode uses XDG-style configuration path
        case .antigravity:
            return "~/.gemini/antigravity/skills"  // Antigravity stores skills under Gemini's config directory
        case .cursor:
            return "~/.cursor/skills"                    // Cursor IDE skills directory
        case .kiro:
            return "~/.kiro/skills"                       // Kiro IDE skills directory
        case .codeBuddy:
            return "~/.codebuddy/skills"             // CodeBuddy AI assistant skills directory
        case .openClaw:
            // Support custom path for Docker/volume mount scenarios
            // Custom path is configured in Settings > General
            if let customPath = AgentPathSettings.customPath(for: self) {
                return customPath
            }
            return "~/.openclaw/skills"                      // OpenClaw AI assistant skills directory
        case .trae:
            return "~/.trae/skills"                         // Trae AI IDE skills directory
        case .qoder:
            return "~/.qoder/skills"                        // Qoder AI coding agent skills directory
        case .qclaw:
            return "~/.qclaw/skills"                        // QClaw AI assistant skills directory
        case .workbuddy:
            return "~/.workbuddy/skills"                    // WorkBuddy AI assistant skills directory
        case .pi:
            return "~/.pi/agent/skills"                     // Pi agent-directory skills (https://pi.dev/docs/latest/configuration)
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
        case .codex: "~/.codex"                // Codex configuration directory
        case .geminiCLI: "~/.gemini"
        case .copilotCLI: "~/.copilot"
        case .openCode: "~/.config/opencode"
        case .antigravity: "~/.gemini/antigravity"
        case .cursor: "~/.cursor"
        case .kiro: "~/.kiro"
        case .codeBuddy: "~/.codebuddy"
        case .openClaw: "~/.openclaw"
        case .trae: "~/.trae"
        case .qoder: "~/.qoder"
        case .qclaw: "~/.qclaw"
        case .workbuddy: "~/.workbuddy"
        case .pi: "~/.pi/agent"
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
        case .kiro: "kiro"
        case .codeBuddy: "codebuddy"
        case .openClaw: "openclaw"
        case .trae: "trae"
        case .qoder: "qoder"
        case .qclaw: "qclaw"
        case .workbuddy: "workbuddy"
        case .pi: "pi"
        }
    }

    /// Shared canonical skills directory URL (~/.agents/skills/)
    /// Used by SkillScanner and agents that read from the shared directory (e.g., OpenCode).
    /// Defined here as a single source of truth to avoid duplicating the path string.
    static let sharedSkillsDirectoryURL: URL = {
        let path = NSString(string: "~/.agents/skills").expandingTildeInPath
        // `isDirectory: true` marks this as a directory URL explicitly. Without it,
        // `URL(fileURLWithPath:)` infers the flag from the filesystem, so the same constant
        // would carry a different trailing-slash state depending on whether the directory
        // already existed when this lazy `static let` was first evaluated.
        return URL(fileURLWithPath: path, isDirectory: true)
    }()

    /// Skills directories of other Agents that this Agent can read in addition to its own skills directory
    ///
    /// This is the "Single Source of Truth" for cross-directory reading rules:
    /// - Copilot CLI can read both ~/.copilot/skills/ and ~/.claude/skills/
    ///   (See GitHub official documentation: https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)
    /// - OpenCode can read both ~/.claude/skills/ and ~/.agents/skills/
    ///   (See: https://opencode.ai/docs/skills/#place-files)
    /// - Qoder loads the legacy ~/.agents/skills/ compatibility directory by default
    ///   (skills.loadFromAgentsDirectory defaults to true)
    /// - Pi natively reads the Agent Skills locations ~/.agents/skills/ and .agents/skills/
    ///   (See: https://pi.dev/docs/latest/skills#add-it-to-pi)
    /// - Other Agents currently do not have cross-directory reading behavior
    ///
    /// Returns an array of tuples: (Directory URL, Source Agent Type)
    /// `sourceAgent` is nil for the shared canonical directory: it is SkillDeck's own store,
    /// not another Agent's directory, so reading it is native support rather than inheritance.
    /// Similar to Java's Pair<URL, AgentType>, Swift uses named tuples for better clarity
    var additionalReadableSkillsDirectories: [(url: URL, sourceAgent: AgentType?)] {
        switch self {
        case .codex:
            // Codex also reads the shared canonical directory ~/.agents/skills/
            // See: https://developers.openai.com/codex/skills/#where-to-save-skills
            // $HOME/.agents/skills is the user-level skills directory for Codex
            return [(Self.sharedSkillsDirectoryURL, nil)]
        case .copilotCLI:
            // Copilot CLI can also read Claude Code's skills directory
            return [(AgentType.claudeCode.skillsDirectoryURL, .claudeCode)]
        case .openCode:
            // OpenCode can also read Claude Code's and the shared canonical skills directories
            // See: https://opencode.ai/docs/skills/#place-files
            return [
                (AgentType.claudeCode.skillsDirectoryURL, .claudeCode),
                (Self.sharedSkillsDirectoryURL, nil)
            ]
        case .cursor:
            // Cursor can also read Claude Code's skills directory
            return [(AgentType.claudeCode.skillsDirectoryURL, .claudeCode)]
        case .qoder:
            // Qoder CLI loads ~/.agents/skills/ by default via the legacy compatibility path
            return [(Self.sharedSkillsDirectoryURL, nil)]
        case .pi:
            // Pi scans the Agent Skills shared location natively. This is also SkillDeck's
            // canonical store, so Pi sees every managed skill without a per-agent symlink.
            return [(Self.sharedSkillsDirectoryURL, nil)]
        default:
            return []
        }
    }

    /// Whether this Agent natively reads SkillDeck's canonical store (~/.agents/skills/).
    /// Agents answering true show canonical-directory skills as "Native support" instead of
    /// an inherited installation, and their assignment toggles stay disabled (Codex, Pi, ...).
    var readsSharedCanonicalDirectory: Bool {
        additionalReadableSkillsDirectories.contains { Self.isCanonicalSharedDirectory($0.url) }
    }

    /// Whether a directory URL denotes the shared canonical skills directory.
    static func isCanonicalSharedDirectory(_ url: URL) -> Bool {
        isSameDirectory(url, sharedSkillsDirectoryURL)
    }

    /// Whether two URLs point at the same directory, ignoring `/a/b` vs `/a/b/` spelling.
    ///
    /// `URL ==` also compares the `hasDirectoryPath` flag, and `URL(fileURLWithPath:)` infers
    /// that flag from the filesystem at call time. So URL equality silently depends on whether
    /// the directory already exists when the URL is built. That passed on a developer machine
    /// (`~/.agents/skills` present) and failed on CI (absent), where canonical skills were
    /// classified as inherited instead of native support. Comparing standardized path strings
    /// removes both sources of instability, because `URL.path` never keeps a trailing slash.
    static func isSameDirectory(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }
}
