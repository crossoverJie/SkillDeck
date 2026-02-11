import Foundation

/// Agent 代表一个已安装的 AI 代码助手实例
/// 使用 struct（值类型）而非 class（引用类型），这是 Swift 的最佳实践
/// 值类型在赋值时会复制，避免了共享状态的并发问题（类似 Go 的值传递）
struct Agent: Identifiable, Hashable {
    let type: AgentType
    let isInstalled: Bool           // CLI 工具是否存在
    let configDirectoryExists: Bool // 配置目录是否存在
    let skillsDirectoryExists: Bool // skills 目录是否存在
    let skillCount: Int             // 该 Agent 下的 skill 数量

    // Identifiable 协议：SwiftUI 用 id 来追踪列表中每个元素
    var id: String { type.id }
    var displayName: String { type.displayName }
}
