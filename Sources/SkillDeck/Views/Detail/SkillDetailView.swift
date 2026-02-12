import SwiftUI

/// SkillDetailView 是 skill 的详情页面（F03）
///
/// 展示 skill 的完整信息，包括：
/// - 基本信息（名称、描述、作者、版本）
/// - Agent 分配状态（可切换）
/// - Markdown 正文
/// - Lock file 信息
/// - 操作按钮（编辑、删除、在 Finder/Terminal 中打开）
struct SkillDetailView: View {

    let skillID: String
    @Bindable var viewModel: SkillDetailViewModel
    @Environment(SkillManager.self) private var skillManager

    /// 编辑器 ViewModel（仅在编辑时创建）
    @State private var editorVM: SkillEditorViewModel?

    var body: some View {
        // guard-let 的 SwiftUI 版本：如果 skill 不存在显示空状态
        if let skill = viewModel.skill(id: skillID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 头部信息
                    headerSection(skill)

                    Divider()

                    // Agent 分配区域
                    agentAssignmentSection(skill)

                    Divider()

                    // Markdown 正文
                    markdownSection(skill)

                    // Lock file 信息
                    if let lockEntry = skill.lockEntry {
                        Divider()
                        lockFileSection(skill, lockEntry)
                    }
                }
                .padding()
            }
            .navigationTitle(skill.displayName)
            .toolbar {
                ToolbarItemGroup {
                    // 在 Finder 中显示
                    Button {
                        viewModel.revealInFinder(skill: skill)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Reveal in Finder")

                    // 在 Terminal 中打开
                    Button {
                        viewModel.openInTerminal(skill: skill)
                    } label: {
                        Image(systemName: "terminal")
                    }
                    .help("Open in Terminal")

                    // 编辑按钮
                    Button {
                        let vm = SkillEditorViewModel(skillManager: skillManager)
                        vm.load(skill: skill)
                        editorVM = vm
                        viewModel.isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .help("Edit SKILL.md")
                }
            }
            // sheet 是 macOS 的模态弹窗（从上方滑入）
            .sheet(isPresented: $viewModel.isEditing) {
                if let editorVM {
                    SkillEditorView(
                        viewModel: editorVM,
                        isPresented: $viewModel.isEditing
                    )
                    .frame(minWidth: 700, minHeight: 500)
                }
            }
        } else {
            EmptyStateView(
                icon: "questionmark.circle",
                title: "Skill Not Found",
                subtitle: "The selected skill may have been deleted"
            )
        }
    }

    // MARK: - Sections

    /// 头部信息区域
    @ViewBuilder
    private func headerSection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(skill.displayName)
                    .font(.title)
                    .fontWeight(.bold)

                ScopeBadge(scope: skill.scope)
            }

            if !skill.metadata.description.isEmpty {
                Text(skill.metadata.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            // 元信息行
            HStack(spacing: 16) {
                if let author = skill.metadata.author {
                    Label(author, systemImage: "person")
                }
                if let version = skill.metadata.version {
                    Label("v\(version)", systemImage: "tag")
                }
                if let license = skill.metadata.license {
                    Label(license, systemImage: "doc.text")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            // 路径显示
            Text(skill.canonicalURL.tildeAbbreviatedPath)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
    }

    /// Agent 分配区域（F06）
    @ViewBuilder
    private func agentAssignmentSection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent Assignment")
                .font(.headline)

            AgentToggleView(skill: skill, viewModel: viewModel)
        }
    }

    /// Markdown 正文区域
    @ViewBuilder
    private func markdownSection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Documentation")
                .font(.headline)

            if skill.markdownBody.isEmpty {
                Text("No documentation available")
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                // 用等宽字体显示 markdown 源码
                // 未来可以替换为渲染后的 markdown
                Text(skill.markdownBody)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
            }
        }
    }

    /// Lock file 信息区域
    @ViewBuilder
    private func lockFileSection(_ skill: Skill, _ lockEntry: LockEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题行：Package Info + 更新检查按钮
            HStack {
                Text("Package Info")
                    .font(.headline)

                Spacer()

                // F12: 更新状态指示和操作按钮
                updateStatusView(skill)
            }

            // Grid 是 macOS 14+ 的网格布局（类似 HTML 的 CSS Grid）
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Source").foregroundStyle(.secondary)
                    Text(lockEntry.source).textSelection(.enabled)
                }
                GridRow {
                    Text("Repository").foregroundStyle(.secondary)
                    Text(lockEntry.sourceUrl).textSelection(.enabled)
                }
                GridRow {
                    Text("Hash").foregroundStyle(.secondary)
                    Text(lockEntry.skillFolderHash)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Installed").foregroundStyle(.secondary)
                    Text(lockEntry.installedAt.formattedDate)
                }
                GridRow {
                    Text("Updated").foregroundStyle(.secondary)
                    Text(lockEntry.updatedAt.formattedDate)
                }
            }
            .font(.subheadline)
        }
    }

    /// F12: 更新状态指示视图
    ///
    /// 根据 viewModel 的更新检查状态显示不同的 UI：
    /// - 检查中：ProgressView + "Checking..."
    /// - 有更新：橙色标签 + "Update" 按钮
    /// - 更新中：ProgressView + "Updating..."
    /// - 已是最新：绿色 checkmark（2秒后自动消失）
    /// - 默认：检查按钮
    @ViewBuilder
    private func updateStatusView(_ skill: Skill) -> some View {
        if viewModel.isCheckingUpdate {
            // 正在检查更新
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.isUpdating {
            // 正在执行更新
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Updating...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if skill.hasUpdate {
            // 有可用更新：显示 hash 对比 + GitHub 链接 + Update 按钮
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Label("Update Available", systemImage: "arrow.up.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Button("Update") {
                        Task { await viewModel.updateSkill(skill) }
                    }
                    .controlSize(.small)
                }

                // Commit hash 对比行 + GitHub 链接
                // 显示 localHash → remoteHash（7 位短格式，与 git log --oneline 一致）
                updateDetailRow(skill)
            }
        } else if viewModel.showUpToDate {
            // 已是最新版本（2秒后自动消失）
            Label("Up to Date", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if let error = viewModel.updateError {
            // 更新检查出错
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            // 默认状态：显示检查按钮
            Button {
                Task { await viewModel.checkForUpdate(skill: skill) }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .controlSize(.small)
            .help("Check for updates")
        }
    }

    /// F12: 更新详情行 —— 显示 commit hash 对比和 GitHub 链接
    ///
    /// 布局：`abc1234 → def5678   View changes on GitHub ↗`
    /// - Hash 对比：本地 commit hash → 远程 commit hash（7 位短格式，与 git log --oneline 一致）
    /// - GitHub 链接：点击在浏览器中打开 compare 页面
    @ViewBuilder
    private func updateDetailRow(_ skill: Skill) -> some View {
        HStack(spacing: 6) {
            // 取前 7 位短格式（与 git log --oneline 一致）
            // prefix(_:) 返回 Substring，需要包在 String() 中
            let localShort = skill.localCommitHash.map { String($0.prefix(7)) }
            let remoteShort = skill.remoteCommitHash.map { String($0.prefix(7)) }

            if let localShort, let remoteShort {
                // 有双方 commit hash：显示对比 `abc1234 → def5678`
                Text("\(localShort) → \(remoteShort)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else if let remoteShort {
                // 只有远程 commit hash（老 skill backfill 未成功时的 fallback）
                Text("→ \(remoteShort)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // GitHub compare 链接按钮
            if let url = githubCompareURL(skill) {
                // 使用 link 风格的文字按钮，点击在浏览器中打开
                // NSWorkspace.shared.open() 是 macOS 中打开 URL 的标准方式
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: 2) {
                        Text("View changes on GitHub")
                        // arrow.up.right 是外部链接图标（↗），表示会跳转到浏览器
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.caption2)
                }
                .buttonStyle(.link)
            }
        }
    }

    // MARK: - Helper Methods

    /// 生成 GitHub compare URL
    ///
    /// 根据 lockEntry.sourceUrl 和 commit hash 生成 GitHub 对比页面 URL：
    /// - 有双方 commit hash: `https://github.com/owner/repo/compare/<local>...<remote>`
    ///   GitHub compare 视图显示两个 commit 之间的所有文件差异
    /// - 只有远程 commit hash: `https://github.com/owner/repo/commit/<remote>`
    ///   显示远程最新 commit 的详情页
    private func githubCompareURL(_ skill: Skill) -> URL? {
        guard let sourceUrl = skill.lockEntry?.sourceUrl,
              let baseURL = GitService.githubWebURL(from: sourceUrl),
              let remoteHash = skill.remoteCommitHash else {
            return nil
        }

        // 如果有本地 commit hash，生成 compare URL 显示两个 commit 之间的差异
        // GitHub compare URL 格式：compare/<base>...<head>
        // 其中 `...` 表示 three-dot diff（显示 head 相对于 base 的变化）
        if let localHash = skill.localCommitHash {
            return URL(string: "\(baseURL)/compare/\(localHash)...\(remoteHash)")
        }

        // 没有本地 commit hash（backfill 未成功），只链接到远程 commit 页面
        return URL(string: "\(baseURL)/commit/\(remoteHash)")
    }
}
