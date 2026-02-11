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

    /// 当前选中的 skill（用于导航到详情页）
    var selectedSkillID: String?

    /// 是否显示删除确认弹窗
    var showDeleteConfirmation = false

    /// 待删除的 skill
    var skillToDelete: Skill?

    /// 排序方式枚举
    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case scope = "Scope"
        case agent = "Agent Count"
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

        // 3. 排序
        switch sortOrder {
        case .name:
            result.sort { $0.displayName.lowercased() < $1.displayName.lowercased() }
        case .scope:
            result.sort { $0.scope.displayName < $1.scope.displayName }
        case .agent:
            result.sort { $0.installations.count > $1.installations.count }
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
