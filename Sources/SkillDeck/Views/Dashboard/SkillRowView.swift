import SwiftUI

/// SkillRowView 是列表中每一行的 skill 卡片
///
/// 显示 skill 名称、描述、scope 徽章、已安装的 Agent 图标
struct SkillRowView: View {

    let skill: Skill

    /// 从环境中获取 SkillManager，用于读取 updateStatuses 字典
    /// @Environment 是 SwiftUI 的依赖注入机制（类似 Spring 的 @Autowired）
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 第一行：名称 + 徽章
            HStack {
                Text(skill.displayName)
                    .font(.headline)

                ScopeBadge(scope: skill.scope)

                // F12: 根据更新检查状态显示不同的指示器图标
                updateStatusIndicator

                Spacer()

                // 已安装的 Agent 图标行
                // 使用 installations 而非 installedAgents，以获取 isInherited 信息
                // 继承安装的图标降低透明度，hover 提示显示来源
                HStack(spacing: 4) {
                    ForEach(skill.installations) { installation in
                        Image(systemName: installation.agentType.iconName)
                            .font(.caption)
                            .foregroundStyle(Constants.AgentColors.color(for: installation.agentType))
                            // 继承安装的图标降低透明度，视觉上区分直接安装和继承安装
                            .opacity(installation.isInherited ? 0.4 : 1.0)
                            // hover 提示：继承安装显示 "Copilot CLI (via ~/.claude/skills)"
                            .help(installation.isInherited && installation.inheritedFrom != nil
                                ? "\(installation.agentType.displayName) (via \(installation.inheritedFrom!.skillsDirectoryPath))"
                                : installation.agentType.displayName)
                    }
                }
            }

            // 第二行：描述（最多显示两行）
            if !skill.metadata.description.isEmpty {
                Text(skill.metadata.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // 第三行：作者 + 版本 + 来源
            HStack(spacing: 12) {
                if let author = skill.metadata.author {
                    Label(author, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let version = skill.metadata.version {
                    Label("v\(version)", systemImage: "tag")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let lockEntry = skill.lockEntry {
                    Label(lockEntry.source, systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Update Status Indicator

    /// 根据 SkillUpdateStatus 枚举渲染不同的状态指示器
    ///
    /// @ViewBuilder 允许在 computed property 中使用条件分支返回不同类型的 View，
    /// 编译器会自动包装为 `some View` 的具体类型（类似 Java 泛型的类型擦除但在编译期解析）。
    /// 使用 `switch` 穷举枚举所有 case（Swift 强制穷举，类似 Rust 的 match）。
    @ViewBuilder
    private var updateStatusIndicator: some View {
        switch skillManager.updateStatuses[skill.id] ?? .notChecked {
        case .notChecked:
            // 默认状态：不显示任何内容
            // EmptyView() 是 SwiftUI 的空视图占位符，不占用任何空间
            EmptyView()
        case .checking:
            // 正在检查：显示旋转的进度指示器（ProgressView）
            // .controlSize(.mini) 使 spinner 更小，适合行内显示
            ProgressView()
                .controlSize(.mini)
        case .hasUpdate:
            // 有可用更新：橙色上箭头实心圆圈图标
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .help("Update available")
        case .upToDate:
            // 已是最新：绿色勾选实心圆圈图标
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
                .help("Up to date")
        case .error(let message):
            // 检查失败：黄色警告三角图标，hover 显示错误详情
            // .help() 设置鼠标悬停时的 tooltip（macOS 原生功能）
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
                .help("Check failed: \(message)")
        }
    }
}
