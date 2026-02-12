import SwiftUI

/// 侧边栏导航项枚举
enum SidebarItem: Hashable {
    case dashboard
    case agent(AgentType)
    case settings

    /// 将侧边栏选项映射为 Agent 过滤器值
    /// - .dashboard / .settings → nil（显示全部 skill）
    /// - .agent(type) → type（仅显示该 Agent 的 skill）
    /// 这个计算属性（computed property）类似 Java 的 getter，每次访问时执行 switch 计算
    var agentFilter: AgentType? {
        switch self {
        case .agent(let agentType):
            return agentType
        case .dashboard, .settings:
            return nil
        }
    }
}

/// SidebarView 是应用的侧边栏导航
///
/// macOS 侧边栏的视觉规范（参考 Finder、Mail 等原生应用）：
/// - 选中项：带圆角矩形的 accentColor 半透明背景
/// - 悬停项：带极淡灰色背景，提示可点击
/// - 普通项：透明背景
///
/// @Binding 是双向绑定（类似 Vue 的 v-model），父组件和子组件共享同一个状态
struct SidebarView: View {

    @Binding var selection: SidebarItem?
    @Environment(SkillManager.self) private var skillManager

    /// 当前鼠标悬停的侧边栏项
    /// @State 是视图私有状态，悬停状态只在本视图内使用，不需要传递给父组件
    @State private var hoveredItem: SidebarItem?

    /// F10: 安装弹窗的 ViewModel（仅在显示 sheet 时创建）
    /// 使用 `.sheet(item:)` 绑定：非 nil 时显示 sheet，nil 时关闭
    /// 这样只用一个 @State 变量同时控制 sheet 的展示和内容，避免双状态同步时序问题
    @State private var installVM: SkillInstallViewModel?

    var body: some View {
        List(selection: $selection) {
            // Section 创建分组（macOS 侧边栏中会显示为可折叠的分组）
            Section("Overview") {
                sidebarRow(item: .dashboard) {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                }
                .badge(skillManager.skills.count)
            }

            Section("Agents") {
                ForEach(AgentType.allCases) { agentType in
                    let agent = skillManager.agents.first { $0.type == agentType }

                    sidebarRow(item: .agent(agentType)) {
                        Label {
                            Text(agentType.displayName)
                        } icon: {
                            Image(systemName: agentType.iconName)
                                .foregroundStyle(Constants.AgentColors.color(for: agentType))
                        }
                    }
                    .badge(skillManager.skills(for: agentType).count)
                    // 使用 skillManager.skills(for:) 而非 agent?.skillCount，
                    // 因为后者只统计 Agent 自身目录的 skill 数量（来自 AgentDetector），
                    // 不包含继承安装（如 Copilot 从 Claude 目录继承的 skill）
                    // opacity 控制透明度：未安装的 Agent 半透明显示
                    .opacity(agent?.isInstalled == true ? 1.0 : 0.5)
                }
            }
        }
        // macOS 侧边栏标准样式
        .listStyle(.sidebar)
        .navigationTitle("SkillDeck")
        // toolbar 添加工具栏按钮
        .toolbar {
            // F10: 安装新 skill 的 "+" 按钮
            ToolbarItem {
                Button {
                    // 设置 installVM 为非 nil 即可触发 .sheet(item:) 显示
                    // 不再需要额外的 showInstallSheet 布尔变量
                    installVM = SkillInstallViewModel(skillManager: skillManager)
                } label: {
                    Image(systemName: "plus")
                }
                .help("Install skill from GitHub")
            }

            // F12: 批量检查所有 skill 的更新
            ToolbarItem {
                Button {
                    Task { await skillManager.checkAllUpdates() }
                } label: {
                    // 检查中时显示旋转动画
                    if skillManager.isCheckingUpdates {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .help("Check all skills for updates")
                .disabled(skillManager.isCheckingUpdates)
            }

            ToolbarItem {
                Button {
                    Task { await skillManager.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh skills")  // 鼠标悬停提示
            }
        }
        // F10: 安装 sheet 弹窗
        // .sheet(item:) 将 sheet 的展示和内容绑定到同一个 Optional 变量：
        // - installVM 非 nil → 显示 sheet，闭包参数 vm 是解包后的值
        // - installVM 为 nil → 关闭 sheet
        // 这比 .sheet(isPresented:) + 额外 @State 更安全，避免双状态同步时序导致首次白窗口
        // onDismiss 在 sheet 关闭时调用 cleanup 清理临时目录
        .sheet(item: $installVM, onDismiss: {
            installVM?.cleanup()
            installVM = nil
        }) { vm in
            SkillInstallView(viewModel: vm)
                // .environment() 将 SkillManager 注入 sheet 中的视图树
                // sheet 创建新的视图层级，需要重新注入环境依赖
                .environment(skillManager)
        }
    }

    /// 构建侧边栏行视图，统一处理点击、选中高亮和悬停效果
    ///
    /// @ViewBuilder 允许闭包返回不同类型的 View（类似 Java 的泛型方法）
    /// `some View` 是 Swift 的不透明返回类型（opaque return type），
    /// 表示"返回某种 View，但调用者不需要知道具体类型"
    @ViewBuilder
    private func sidebarRow<Label: View>(
        item: SidebarItem,
        @ViewBuilder label: () -> Label
    ) -> some View {
        // Button 确保点击一定能更新 selection（部分 macOS 版本 List 原生选择不可靠）
        Button { selection = item } label: { label() }
            // .buttonStyle(.plain) 去掉按钮默认样式（边框、按压效果等）
            .buttonStyle(.plain)
            // .contentShape(Rectangle()) 将交互区域（点击+悬停）扩展到整个行矩形
            // 默认情况下 Button 只在内容（文字/图标）区域响应事件，
            // 行的空白区域不触发 .onHover，导致悬停效果只在文字上方才出现
            // 类似 CSS 的 pointer-events: all + width: 100%
            .contentShape(Rectangle())
            // .tag 关联选中值，让 List 知道这一行对应哪个 SidebarItem
            .tag(item)
            // .onHover 监听鼠标进入/离开事件（macOS 特有，类似 CSS 的 :hover）
            // 闭包参数 isHovering: Bool 表示鼠标是否在元素上方
            .onHover { isHovering in
                // 使用 withAnimation 添加过渡动画，.easeInOut 是缓入缓出曲线
                // duration: 0.15 是 150 毫秒，足够快但不突兀
                withAnimation(.easeInOut(duration: 0.15)) {
                    hoveredItem = isHovering ? item : nil
                }
            }
            // .listRowBackground 自定义列表行的背景（覆盖 List 默认的选中/悬停样式）
            // 这里用 RoundedRectangle 画圆角矩形，模拟 macOS 原生侧边栏的选中/悬停效果
            .listRowBackground(
                RoundedRectangle(cornerRadius: 6)
                    .fill(rowBackground(for: item))
            )
    }

    /// 根据选中/悬停状态返回行背景颜色
    /// macOS 原生侧边栏的颜色规范：
    /// - 选中：accentColor（系统强调色，默认蓝色）+ 低透明度
    /// - 悬停：primary（自适应黑/白）+ 极低透明度
    /// - 普通：完全透明
    private func rowBackground(for item: SidebarItem) -> Color {
        if selection == item {
            // 选中状态：如果是 Agent 项，使用该 Agent 的品牌色；Dashboard/Settings 保持系统 accentColor
            // Swift 5.9 的 if/else 表达式语法：可以直接在 let 赋值中使用 if-else，类似三元运算符但支持 pattern matching
            let baseColor: Color = if case .agent(let agentType) = item {
                Constants.AgentColors.color(for: agentType)
            } else {
                Color.accentColor
            }
            return baseColor.opacity(0.15)
        } else if hoveredItem == item {
            // 悬停状态：极淡的灰色背景，提示"这个可以点击"
            return Color.primary.opacity(0.08)
        }
        // 普通状态：透明
        return Color.clear
    }
}
