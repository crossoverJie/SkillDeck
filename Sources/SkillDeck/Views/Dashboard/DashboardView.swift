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
            ToolbarItemGroup {
                // Picker 在工具栏中会渲染成下拉菜单
                Picker("Sort", selection: $viewModel.sortOrder) {
                    ForEach(DashboardViewModel.SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }

                Picker("Agent", selection: $viewModel.selectedAgentFilter) {
                    Text("All Agents").tag(AgentType?.none)
                    Divider()
                    ForEach(AgentType.allCases) { agent in
                        Label(agent.displayName, systemImage: agent.iconName)
                            .tag(AgentType?.some(agent))
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
