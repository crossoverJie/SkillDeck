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
                        lockFileSection(lockEntry)
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
    private func lockFileSection(_ lockEntry: LockEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Package Info")
                .font(.headline)

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
}
