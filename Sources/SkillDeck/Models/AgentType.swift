import Foundation

/// AgentType 表示支持的 AI 代码助手类型
/// 类似 Java 的 enum，但 Swift 的 enum 更强大，可以有关联值和方法
enum AgentType: String, CaseIterable, Identifiable, Codable {
    case claudeCode = "claude-code"
    case codex = "codex"
    case geminiCLI = "gemini-cli"
    case copilotCLI = "copilot-cli"
    case openCode = "opencode"       // OpenCode: 开源 AI 编程 CLI 工具

    // Identifiable 协议要求（类似 Java 的 Comparable），SwiftUI 列表渲染需要
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .geminiCLI: "Gemini CLI"
        case .copilotCLI: "Copilot CLI"
        case .openCode: "OpenCode"
        }
    }

    /// 每个 Agent 的配色，用于 UI 区分
    /// SwiftUI 使用 Color 类型，类似 Android 的 Color
    var brandColor: String {
        switch self {
        case .claudeCode: "coral"     // #E8734A
        case .codex: "green"
        case .geminiCLI: "blue"
        case .copilotCLI: "purple"
        case .openCode: "teal"
        }
    }

    /// Agent 对应的 SF Symbol 图标名
    /// SF Symbols 是 Apple 提供的系统图标库，类似 Material Icons
    var iconName: String {
        switch self {
        case .claudeCode: "brain.head.profile"
        case .codex: "terminal"
        case .geminiCLI: "sparkles"
        case .copilotCLI: "airplane"
        case .openCode: "chevron.left.forwardslash.chevron.right"  // </> 代码符号，契合 OpenCode 的编程主题
        }
    }

    /// Agent 的用户级 skills 目录路径
    /// ~ 代表用户 home 目录，例如 /Users/chenjie
    var skillsDirectoryPath: String {
        switch self {
        case .claudeCode: "~/.claude/skills"
        case .codex: "~/.agents/skills"     // Codex 直接使用共享目录
        case .geminiCLI: "~/.gemini/skills"
        case .copilotCLI: "~/.copilot/skills"
        case .openCode: "~/.config/opencode/skills"  // OpenCode 使用 XDG 风格的配置路径
        }
    }

    /// 解析后的绝对路径 URL
    var skillsDirectoryURL: URL {
        let expanded = NSString(string: skillsDirectoryPath).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    /// Agent 的配置目录
    var configDirectoryPath: String? {
        switch self {
        case .claudeCode: "~/.claude"
        case .codex: nil                    // Codex 没有独立配置目录
        case .geminiCLI: "~/.gemini"
        case .copilotCLI: "~/.copilot"
        case .openCode: "~/.config/opencode"
        }
    }

    /// 用于检测 Agent 是否安装的 CLI 命令
    var detectCommand: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .geminiCLI: "gemini"
        case .copilotCLI: "gh"
        case .openCode: "opencode"
        }
    }

    /// 该 Agent 除了自身 skills 目录外，还能额外读取的其他 Agent 的 skills 目录
    ///
    /// 这是跨目录读取规则的「唯一真实来源」（Single Source of Truth）：
    /// - Copilot CLI 能同时读取 ~/.copilot/skills/ 和 ~/.claude/skills/
    ///   （参见 GitHub 官方文档：https://docs.github.com/en/copilot/concepts/agents/about-agent-skills）
    /// - 其他 Agent 目前没有跨目录读取的行为
    ///
    /// 返回元组数组：(目录 URL, 来源 Agent 类型)
    /// 类似 Java 的 Pair<URL, AgentType>，Swift 用命名元组更直观
    var additionalReadableSkillsDirectories: [(url: URL, sourceAgent: AgentType)] {
        switch self {
        case .copilotCLI:
            // Copilot CLI 还能读取 Claude Code 的 skills 目录
            return [(AgentType.claudeCode.skillsDirectoryURL, .claudeCode)]
        default:
            return []
        }
    }
}
