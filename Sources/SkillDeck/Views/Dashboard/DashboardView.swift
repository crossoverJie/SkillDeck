import SwiftUI

/// DashboardView 是 skill 列表页面（F02）
///
/// 展示所有已安装的 skill，支持搜索、过滤和排序
struct DashboardView: View {

    /// @Bindable 让 @Observable 对象的属性可以用 $ 前缀创建 Binding
    /// 例如 $viewModel.searchText 创建一个 Binding<String>
    @Bindable var viewModel: DashboardViewModel
    @Binding var selectedSkillID: String?
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        Group {
            if skillManager.isLoading && skillManager.skills.isEmpty {
                // 首次加载时显示进度指示器
                ProgressView("Scanning skills...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredSkills.isEmpty {
                // 空状态
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Skills Found",
                    subtitle: viewModel.searchText.isEmpty
                        ? "Install skills using npx skills add or the CLI"
                        : "No skills match your search"
                )
            } else {
                // Skill 列表
                List(viewModel.filteredSkills, selection: $selectedSkillID) { skill in
                    SkillRowView(skill: skill)
                        .tag(skill.id)
                        // contextMenu 是 macOS 的右键菜单
                        .contextMenu {
                            Button("Open in Finder") {
                                NSWorkspace.shared.selectFile(
                                    nil,
                                    inFileViewerRootedAtPath: skill.canonicalURL.path
                                )
                            }
                            Divider()  // 菜单分隔线
                            Button("Delete", role: .destructive) {
                                viewModel.requestDelete(skill: skill)
                            }
                        }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .navigationTitle(navigationTitle)
        // 搜索栏（macOS 标准搜索框，显示在工具栏）
        .searchable(text: $viewModel.searchText, prompt: "Search skills...")
        // 工具栏：排序和过滤
        .toolbar {
            // placement: .navigation 将工具栏项放在左侧（导航区域），默认 .automatic 会放在右侧
            ToolbarItemGroup(placement: .navigation) {
                Menu {
                    // Section 在菜单中创建带标题的分组，类似 Android 的 menu group
                    Section("Sort By") {
                        ForEach(DashboardViewModel.SortOrder.allCases, id: \.self) { order in
                            Button {
                                if viewModel.sortOrder == order {
                                    // 点击已选中的排序字段 → 切换升序/降序
                                    viewModel.sortDirection = viewModel.sortDirection.toggled
                                } else {
                                    // 点击新的排序字段 → 切换到该字段，重置为升序
                                    viewModel.sortOrder = order
                                    viewModel.sortDirection = .ascending
                                }
                            } label: {
                                // HStack 水平排列：图标 + 文字 + 排序方向箭头
                                HStack {
                                    Label(order.rawValue, systemImage: order.iconName)
                                    if viewModel.sortOrder == order {
                                        // Spacer 把箭头推到右边
                                        Spacer()
                                        Image(systemName: viewModel.sortDirection.iconName)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    // 工具栏按钮的外观：排序图标 + 当前排序字段 + 方向箭头
                    // Label 同时提供文字和图标，macOS 工具栏会根据空间决定显示哪个
                    HStack(spacing: 2) {
                        Image(systemName: "line.3.horizontal.decrease")
                        Text(viewModel.sortOrder.rawValue)
                        Image(systemName: viewModel.sortDirection.iconName)
                            .font(.caption2)
                            // imageScale 控制 SF Symbol 的大小
                            .imageScale(.small)
                    }
                }
            }
        }
        // 删除确认弹窗
        // .alert 类似 Android 的 AlertDialog 或 Web 的 confirm()
        .alert("Delete Skill", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
            Button("Delete", role: .destructive) {
                Task { await viewModel.confirmDelete() }
            }
        } message: {
            if let skill = viewModel.skillToDelete {
                Text("Are you sure you want to delete \"\(skill.displayName)\"? This will remove the skill directory and all symlinks. This action cannot be undone.")
            }
        }
        // 错误提示
        .overlay(alignment: .bottom) {
            if let error = skillManager.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error)
                    Spacer()
                    Button("Dismiss") {
                        skillManager.errorMessage = nil
                    }
                    .buttonStyle(.borderless)
                }
                .padding()
                .background(.red.opacity(0.1))
                .cornerRadius(8)
                .padding()
            }
        }
    }

    private var navigationTitle: String {
        if let agent = viewModel.selectedAgentFilter {
            return agent.displayName
        }
        return "All Skills"
    }
}
