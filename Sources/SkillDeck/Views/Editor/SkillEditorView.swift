import SwiftUI

/// SkillEditorView is the SKILL.md editor (F05)
///
/// Split into two panels:
/// - Left: YAML frontmatter form + Markdown editor
/// - Right: Live Markdown preview
///
/// Presented as a sheet (modal dialog)
struct SkillEditorView: View {

    @Bindable var viewModel: SkillEditorViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            editorToolbar

            Divider()

            // Editor area (split into two panels)
            HSplitView {
                // Left: form + Markdown editing
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        formSection
                        markdownEditorSection
                    }
                    .padding()
                }
                .frame(minWidth: 350)

                // Right: Markdown preview
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

            // Save status indicator
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

            // Cancel button
            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)  // Esc key

            // Save button
            Button("Save") {
                Task { await viewModel.save() }
            }
            .keyboardShortcut(.defaultAction)  // Enter key
            .disabled(viewModel.isSaving)
        }
        .padding()
    }

    // MARK: - Form Section

    /// YAML frontmatter form
    private var formSection: some View {
        GroupBox("Metadata") {
            VStack(spacing: 12) {
                // LabeledContent + TextField creates standard form row
                LabeledContent("Name") {
                    TextField("Skill name", text: $viewModel.name)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Description") {
                    // TextEditor is a multi-line text editor (similar to HTML textarea)
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

    /// Markdown body editor
    private var markdownEditorSection: some View {
        GroupBox("Markdown Content") {
            TextEditor(text: $viewModel.markdownBody)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 200)
        }
    }
}
