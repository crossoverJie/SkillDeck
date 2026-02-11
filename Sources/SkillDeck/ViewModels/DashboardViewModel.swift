import Foundation

/// DashboardViewModel 管理 Dashboard 页面的状态和交互逻辑
///
/// 在 MVVM 架构中，ViewModel 是 View 和 Model 之间的桥梁：
/// - View 通过数据绑定观察 ViewModel 的状态变化
/// - View 的用户操作调用 ViewModel 的方法
/// - ViewModel 调用 Service 层处理业务逻辑
///
/// @Observable 让 SwiftUI 自动追踪属性变化并刷新 UI
/// @MainActor 确保所有状态修改在主线程上执行（UI 安全）
@MainActor
@Observable
final class DashboardViewModel {

    /// 搜索关键词
    var searchText = ""

    /// 当前选中的 Agent 过滤器（nil 表示显示全部）
    var selectedAgentFilter: AgentType?

    /// 排序方式
    var sortOrder: SortOrder = .name

    /// 排序方向（升序/降序）
    var sortDirection: SortDirection = .ascending

    /// 当前选中的 skill（用于导航到详情页）
    var selectedSkillID: String?

    /// 是否显示删除确认弹窗
    var showDeleteConfirmation = false

    /// 待删除的 skill
    var skillToDelete: Skill?

    /// 排序方向枚举
    /// Swift 的 enum 可以实现多个协议：
    /// - CaseIterable: 提供 allCases 集合，用于遍历所有枚举值
    enum SortDirection: CaseIterable {
        case ascending
        case descending

        /// 切换排序方向，返回相反方向
        var toggled: SortDirection {
            self == .ascending ? .descending : .ascending
        }

        /// SF Symbols 图标名：升序用向上箭头，降序用向下箭头
        var iconName: String {
            self == .ascending ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"
        }

        /// 显示文本
        var displayName: String {
            self == .ascending ? "Ascending" : "Descending"
        }
    }

    /// 排序方式枚举
    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case scope = "Scope"
        case agent = "Agent Count"

        /// 每种排序方式对应一个 SF Symbol 图标
        var iconName: String {
            switch self {
            case .name: return "textformat.abc"
            case .scope: return "scope"
            case .agent: return "cpu"
            }
        }
    }

    /// 引用全局的 SkillManager（依赖注入）
    let skillManager: SkillManager

    init(skillManager: SkillManager) {
        self.skillManager = skillManager
    }

    /// 根据当前的搜索、过滤和排序条件，计算要显示的 skill 列表
    /// computed property（计算属性）：每次访问时动态计算，类似 Java 的 getter
    var filteredSkills: [Skill] {
        var result = skillManager.skills

        // 1. 搜索过滤
        if !searchText.isEmpty {
            result = skillManager.search(query: searchText)
        }

        // 2. Agent 过滤
        if let agent = selectedAgentFilter {
            result = result.filter { skill in
                skill.installations.contains { $0.agentType == agent }
            }
        }

        // 3. 排序（根据排序方向决定升序或降序）
        // Swift 的闭包中 $0、$1 是匿名参数，类似 Kotlin 的 it
        let ascending = sortDirection == .ascending
        switch sortOrder {
        case .name:
            result.sort {
                ascending
                    ? $0.displayName.lowercased() < $1.displayName.lowercased()
                    : $0.displayName.lowercased() > $1.displayName.lowercased()
            }
        case .scope:
            result.sort {
                ascending
                    ? $0.scope.displayName < $1.scope.displayName
                    : $0.scope.displayName > $1.scope.displayName
            }
        case .agent:
            // Agent Count 默认降序更直观（最多的排前面）
            result.sort {
                ascending
                    ? $0.installations.count < $1.installations.count
                    : $0.installations.count > $1.installations.count
            }
        }

        return result
    }

    /// 请求删除 skill（先显示确认弹窗）
    func requestDelete(skill: Skill) {
        skillToDelete = skill
        showDeleteConfirmation = true
    }

    /// 确认删除
    func confirmDelete() async {
        guard let skill = skillToDelete else { return }
        do {
            try await skillManager.deleteSkill(skill)
        } catch {
            skillManager.errorMessage = "Delete failed: \(error.localizedDescription)"
        }
        skillToDelete = nil
        showDeleteConfirmation = false
    }

    /// 取消删除
    func cancelDelete() {
        skillToDelete = nil
        showDeleteConfirmation = false
    }
}
