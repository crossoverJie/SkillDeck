import SwiftUI

/// SkillEditorView 是 SKILL.md 的编辑器（F05）
///
/// 分为左右两个面板：
/// - 左侧：YAML frontmatter 表单 + Markdown 编辑器
/// - 右侧：Markdown 实时预览
///
/// 使用 sheet 形式呈现（模态弹窗）
struct SkillEditorView: View {

    @Bindable var viewModel: SkillEditorViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            editorToolbar

            Divider()

            // 编辑区域（左右分栏）
            HSplitView {
                // 左侧：表单 + Markdown 编辑
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        formSection
                        markdownEditorSection
                    }
                    .padding()
                }
                .frame(minWidth: 350)

                // 右侧：Markdown 预览
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text(viewModel.markdownBody)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding()
                }
                .frame(minWidth: 300)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    // MARK: - Editor Toolbar

    private var editorToolbar: some View {
        HStack {
            Text("Edit SKILL.md")
                .font(.headline)

            Spacer()

            // 保存状态指示
            if viewModel.saveSuccess {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }

            if let error = viewModel.saveError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            // 取消按钮
            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)  // Esc 键

            // 保存按钮
            Button("Save") {
                Task { await viewModel.save() }
            }
            .keyboardShortcut(.defaultAction)  // Enter 键
            .disabled(viewModel.isSaving)
        }
        .padding()
    }

    // MARK: - Form Section

    /// YAML frontmatter 表单
    private var formSection: some View {
        GroupBox("Metadata") {
            VStack(spacing: 12) {
                // LabeledContent + TextField 创建标准的表单行
                LabeledContent("Name") {
                    TextField("Skill name", text: $viewModel.name)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Description") {
                    // TextEditor 是多行文本编辑器（类似 HTML 的 textarea）
                    TextEditor(text: $viewModel.description)
                        .font(.body)
                        .frame(height: 60)
                        .border(Color(nsColor: .separatorColor))
                }

                HStack(spacing: 16) {
                    LabeledContent("Author") {
                        TextField("Author", text: $viewModel.author)
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent("Version") {
                        TextField("1.0", text: $viewModel.version)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                LabeledContent("License") {
                    TextField("MIT, Apache-2.0, etc.", text: $viewModel.license)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Allowed Tools") {
                    TextField("e.g., Bash(cmd *)", text: $viewModel.allowedTools)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Markdown Editor Section

    /// Markdown 正文编辑器
    private var markdownEditorSection: some View {
        GroupBox("Markdown Content") {
            TextEditor(text: $viewModel.markdownBody)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 200)
        }
    }
}
