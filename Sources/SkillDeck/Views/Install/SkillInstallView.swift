import SwiftUI

/// SkillInstallView 是 F10（一键安装）的弹窗界面
///
/// 两步流程：
/// 1. 输入 GitHub 仓库 URL → 点击 "Scan" 扫描
/// 2. 选择要安装的 skill 和目标 Agent → 点击 "Install" 安装
///
/// 使用 `.sheet()` 从 SidebarView 弹出，关闭时自动清理临时目录
struct SkillInstallView: View {

    /// ViewModel 管理安装流程状态
    /// @Bindable 让 @Observable 对象的属性可以创建 Binding（双向绑定）
    @Bindable var viewModel: SkillInstallViewModel

    /// 从环境中获取 dismiss 动作，用于关闭 sheet
    /// @Environment(\.dismiss) 是 SwiftUI 提供的标准方式来关闭当前呈现的视图（sheet/popover 等）
    /// 替代之前的 @Binding var isPresented，更解耦——子视图不需要知道父视图用什么方式控制显示
    @Environment(\.dismiss) private var dismiss

    /// 从环境中获取 SkillManager（用于检查已检测到的 Agent）
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            headerBar

            Divider()

            // 根据当前阶段显示不同内容
            // Swift 的 switch 是表达式，可以直接在 ViewBuilder 中使用
            switch viewModel.phase {
            case .inputURL:
                inputURLPhase
            case .fetching:
                fetchingPhase
            case .selectSkills:
                selectSkillsPhase
            case .installing:
                installingPhase
            case .completed:
                completedPhase
            case .error(let message):
                errorPhase(message)
            }
        }
        // sheet 弹窗的最小尺寸（macOS 标准做法）
        .frame(minWidth: 550, minHeight: 400)
    }

    // MARK: - Header

    /// 标题栏（所有阶段通用）
    private var headerBar: some View {
        HStack {
            Text("Install Skills from GitHub")
                .font(.headline)
            Spacer()
            // 关闭按钮
            Button {
                // dismiss() 关闭当前 sheet，由 SwiftUI 环境提供
                // 父视图的 .sheet(item:) onDismiss 回调会自动触发 cleanup
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Phase Views

    /// 阶段 1：输入 URL
    private var inputURLPhase: some View {
        VStack(spacing: 16) {
            Spacer()

            // 图标和说明
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Enter a GitHub repository to scan for skills")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // URL 输入框
            // TextField 类似 HTML 的 <input type="text">，placeholder 是灰色提示文字
            HStack {
                TextField("owner/repo or GitHub URL", text: $viewModel.repoURLInput)
                    .textFieldStyle(.roundedBorder)
                    // onSubmit 监听回车键事件（类似 HTML form 的 submit）
                    .onSubmit {
                        guard !viewModel.repoURLInput.isEmpty else { return }
                        Task { await viewModel.fetchRepository() }
                    }

                Button("Scan") {
                    Task { await viewModel.fetchRepository() }
                }
                .disabled(viewModel.repoURLInput.trimmingCharacters(in: .whitespaces).isEmpty)
                // .keyboardShortcut(.return) 让按钮响应回车键
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
    }

    /// 阶段：正在克隆和扫描
    private var fetchingPhase: some View {
        VStack(spacing: 16) {
            Spacer()
            // ProgressView 是 macOS 原生的加载指示器（旋转的菊花）
            ProgressView()
                .controlSize(.large)
            Text(viewModel.progressMessage)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    /// 阶段 2：选择 skill 和 Agent
    private var selectSkillsPhase: some View {
        VStack(spacing: 0) {
            // Skill 列表（可滚动）
            // List 是 macOS 原生列表组件，自带选中、滚动等行为
            List {
                Section("Skills Found (\(viewModel.discoveredSkills.count))") {
                    ForEach(viewModel.discoveredSkills) { skill in
                        skillRow(skill)
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            // Agent 选择区域 + 安装按钮
            VStack(spacing: 12) {
                // Agent 复选框行
                HStack(spacing: 16) {
                    Text("Install to:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // ForEach 遍历所有已检测到的 Agent
                    ForEach(AgentType.allCases) { agentType in
                        let isDetected = skillManager.agents.first { $0.type == agentType }?.isInstalled == true
                        // Toggle 是 macOS 的开关/复选框组件
                        Toggle(isOn: Binding(
                            get: { viewModel.selectedAgents.contains(agentType) },
                            set: { _ in viewModel.toggleAgentSelection(agentType) }
                        )) {
                            Label(agentType.displayName, systemImage: agentType.iconName)
                                .font(.caption)
                        }
                        .toggleStyle(.checkbox)
                        // 未安装的 Agent 降低透明度但仍可选择
                        .opacity(isDetected ? 1.0 : 0.5)
                    }

                    Spacer()
                }

                // 安装按钮
                HStack {
                    // 选中数量提示
                    let selectedCount = viewModel.selectedSkillNames.count
                    Text("\(selectedCount) skill\(selectedCount == 1 ? "" : "s") selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Install") {
                        Task { await viewModel.installSelected() }
                    }
                    .disabled(viewModel.selectedSkillNames.isEmpty || viewModel.selectedAgents.isEmpty)
                    // .buttonStyle(.borderedProminent) 使按钮显示为填充的强调色样式
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    /// 阶段：正在安装
    private var installingPhase: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(viewModel.progressMessage)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    /// 阶段：安装完成
    private var completedPhase: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Installation Complete")
                .font(.headline)

            Text("\(viewModel.installedCount) skill\(viewModel.installedCount == 1 ? "" : "s") installed successfully")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                // "Install More" 按钮：重置状态重新开始
                Button("Install More") {
                    viewModel.reset()
                }

                Button("Done") {
                    // dismiss() 关闭当前 sheet
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
    }

    /// 阶段：错误
    /// - Parameter message: 错误信息
    private func errorPhase(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Something went wrong")
                .font(.headline)

            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try Again") {
                viewModel.reset()
            }

            Spacer()
        }
    }

    // MARK: - Skill Row

    /// Skill 列表行：复选框 + 名称 + 描述 + "Already installed" 徽章
    @ViewBuilder
    private func skillRow(_ skill: GitService.DiscoveredSkill) -> some View {
        let isAlreadyInstalled = viewModel.alreadyInstalledNames.contains(skill.id)

        HStack {
            // 复选框
            // Toggle + checkbox 样式 = macOS 原生复选框
            Toggle(isOn: Binding(
                get: { viewModel.selectedSkillNames.contains(skill.id) },
                set: { _ in viewModel.toggleSkillSelection(skill.id) }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .disabled(isAlreadyInstalled)

            // Skill 信息
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(skill.metadata.name.isEmpty ? skill.id : skill.metadata.name)
                        .font(.body)
                        .fontWeight(.medium)

                    // "Already installed" 徽章
                    if isAlreadyInstalled {
                        Text("Installed")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            // clipShape 裁剪视图形状为胶囊形（两端圆角的矩形）
                            .clipShape(Capsule())
                    }
                }

                if !skill.metadata.description.isEmpty {
                    Text(skill.metadata.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        // 行透明度：已安装的 skill 降低透明度
        .opacity(isAlreadyInstalled ? 0.6 : 1.0)
    }
}
