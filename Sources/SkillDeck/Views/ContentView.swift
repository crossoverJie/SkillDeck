import SwiftUI

/// ContentView 是应用的根视图
///
/// NavigationSplitView 是 macOS 的三栏导航布局（类似 Apple Mail）：
/// - 左栏（sidebar）：导航菜单
/// - 中栏（content）：列表
/// - 右栏（detail）：详情
///
/// @Environment 从 View 树中获取注入的对象（类似 React 的 useContext）
/// SkillManager 在 SkillDeckApp.swift 中通过 .environment() 注入
struct ContentView: View {

    @Environment(SkillManager.self) private var skillManager

    /// NavigationSplitView 的侧边栏可见性状态
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    /// 侧边栏当前选中项
    @State private var selectedSidebarItem: SidebarItem? = .dashboard

    /// 当前选中的 skill ID（用于导航到详情页）
    @State private var selectedSkillID: String?

    /// Dashboard ViewModel
    @State private var dashboardVM: DashboardViewModel?

    /// Detail ViewModel
    @State private var detailVM: SkillDetailViewModel?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // 左栏：侧边栏导航
            SidebarView(selection: $selectedSidebarItem)
        } content: {
            // 中栏：skill 列表
            if let vm = dashboardVM {
                DashboardView(viewModel: vm, selectedSkillID: $selectedSkillID)
            }
        } detail: {
            // 右栏：skill 详情
            if let skillID = selectedSkillID, let vm = detailVM {
                SkillDetailView(skillID: skillID, viewModel: vm)
            } else {
                EmptyStateView(
                    icon: "square.stack.3d.up",
                    title: "Select a Skill",
                    subtitle: "Choose a skill from the list to view its details"
                )
            }
        }
        // .task 在 View 首次出现时执行异步任务（类似 React 的 useEffect([], ...)）
        .task {
            dashboardVM = DashboardViewModel(skillManager: skillManager)
            detailVM = SkillDetailViewModel(skillManager: skillManager)
            await skillManager.refresh()
        }
        // .onChange(of:) 在指定值变化时触发闭包（类似 React 的 useEffect 带依赖数组）
        // 当用户点击侧边栏导航项时，将选中项映射为 Agent 过滤器并同步到 DashboardViewModel
        // 实现侧边栏点击 → Dashboard 列表筛选的联动效果
        .onChange(of: selectedSidebarItem) { _, newValue in
            dashboardVM?.selectedAgentFilter = newValue?.agentFilter
        }
    }
}
