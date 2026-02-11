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
                    .badge(agent?.skillCount ?? 0)
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
            ToolbarItem {
                Button {
                    Task { await skillManager.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh skills")  // 鼠标悬停提示
            }
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
