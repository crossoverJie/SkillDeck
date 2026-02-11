import SwiftUI

/// 侧边栏导航项枚举
enum SidebarItem: Hashable {
    case dashboard
    case agent(AgentType)
    case settings
}

/// SidebarView 是应用的侧边栏导航
///
/// List 在 macOS 上带 sidebar 样式时会渲染成标准的侧边栏外观
/// @Binding 是双向绑定（类似 Vue 的 v-model），父组件和子组件共享同一个状态
struct SidebarView: View {

    @Binding var selection: SidebarItem?
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        List(selection: $selection) {
            // Section 创建分组（macOS 侧边栏中会显示为可折叠的分组）
            Section("Overview") {
                Label("Dashboard", systemImage: "square.grid.2x2")
                    // .tag 关联选中值，当用户点击时 selection 会被设置为这个 tag
                    .tag(SidebarItem.dashboard)
                    .badge(skillManager.skills.count)
            }

            Section("Agents") {
                ForEach(AgentType.allCases) { agentType in
                    let agent = skillManager.agents.first { $0.type == agentType }

                    Label {
                        Text(agentType.displayName)
                    } icon: {
                        Image(systemName: agentType.iconName)
                            .foregroundStyle(Constants.AgentColors.color(for: agentType))
                    }
                    .tag(SidebarItem.agent(agentType))
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
}
