import SwiftUI

/// Constants 集中管理应用的全局常量
/// 使用 enum 作为命名空间（namespace），因为 enum 没有 case 时不能被实例化
/// 这是 Swift 中创建纯命名空间的最佳实践（类似 Java 的 private constructor + static fields）
enum Constants {

    /// 应用级别的 Agent 品牌色
    /// SwiftUI 的 Color 类似 Android 的 Color 或 CSS 的 color
    enum AgentColors {
        static func color(for agent: AgentType) -> Color {
            switch agent {
            case .claudeCode: Color(red: 0.91, green: 0.45, blue: 0.29)   // Coral #E8734A
            case .codex:      Color(red: 0.20, green: 0.78, blue: 0.35)   // Green
            case .geminiCLI:  Color(red: 0.26, green: 0.52, blue: 0.96)   // Blue
            case .copilotCLI: Color(red: 0.58, green: 0.34, blue: 0.92)   // Purple
            case .openCode:   Color(red: 0.0, green: 0.71, blue: 0.67)    // Teal #00B5AB
            }
        }
    }

    /// Scope 徽章颜色
    enum ScopeColors {
        static func color(for scope: SkillScope) -> Color {
            switch scope {
            case .sharedGlobal: .blue
            case .agentLocal:   .secondary
            case .project:      .green
            }
        }
    }

    /// 共享 skills 目录路径
    static let sharedSkillsPath = "~/.agents/skills"

    /// Lock file 路径
    static let lockFilePath = "~/.agents/.skill-lock.json"
}
