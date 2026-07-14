import AppKit
import SwiftUI

/// The middle column mirrors DashboardView: it is a list of first-class projects, not a picker
/// combined with a second list. Selecting a row drives the whole right-hand project workspace.
struct ProjectTargetList: View {
    @Bindable var manager: ProjectManager

    var body: some View {
        Group {
            if manager.projects.isEmpty {
                ContentUnavailableView(
                    "尚未添加项目",
                    systemImage: "folder.badge.plus",
                    description: Text("添加一个项目根目录后，SkillDeck 只会扫描其直接下的 .agents/skills。")
                )
            } else {
                List(manager.projects, selection: $manager.selectedProjectID) { project in
                    ProjectRow(project: project, manager: manager)
                        .tag(Optional(project.id))
                        .contextMenu {
                            Button("在 Finder 中显示") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.rootPath)
                            }
                            Divider()
                            Button("移除项目", role: .destructive) {
                                manager.remove(projectID: project.id)
                            }
                        }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .navigationTitle("项目")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: chooseProject) {
                    Image(systemName: "plus")
                }
                .help("添加项目")
            }
            ToolbarItem {
                Button { manager.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help("重新扫描项目")
            }
        }
        .onChange(of: manager.selectedProjectID) { _, projectID in
            manager.select(project: projectID, target: manager.selectedTargetID)
        }
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择项目根目录"
        if panel.runModal() == .OK, let url = panel.url {
            manager.addProject(url)
        }
    }
}

/// ProjectRow uses the same compact hierarchy as SkillRowView: name, source location, then status.
private struct ProjectRow: View {
    let project: ManagedProject
    let manager: ProjectManager

    private var inspections: [ProjectInspection] {
        manager.inspections.filter { $0.project.id == project.id }
    }

    private var sourceCount: Int {
        inspections.first?.skills.count ?? 0
    }

    private var fullySyncedTargets: Int {
        inspections.filter { inspection in
            inspection.isWholeDirectorySynced
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(project.name, systemImage: "folder")
                    .appFont(.headline)
                Spacer()
                Text("\(sourceCount) 个技能")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(project.rootURL.tildeAbbreviatedPath)
                .appFont(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Label("\(fullySyncedTargets)/\(manager.targets.count) 个工具已完全同步", systemImage: "link")
                .appFont(.caption)
                .foregroundStyle(fullySyncedTargets == manager.targets.count && sourceCount > 0 ? .green : .secondary)
        }
        .padding(.vertical, 4)
    }
}

/// The detail pane has a visible agent status rail. It avoids a second navigation list while
/// keeping target selection direct and discoverable for projects with many configured agents.
struct ProjectSyncDetail: View {
    @Bindable var manager: ProjectManager
    @Environment(SkillManager.self) private var skillManager
    @State private var selectedSourceSkill: ProjectSkillRow?

    var body: some View {
        if let project = manager.projects.first(where: { $0.id == manager.selectedProjectID }),
           let inspection = manager.selectedInspection {
            VStack(alignment: .leading, spacing: 0) {
                projectHeader(project)
                rulesSection(project)
                Divider()
                agentRail(project)
                Divider()
                skillsContent(inspection)
                Divider()
                actionBar(inspection)
            }
            .navigationTitle(project.name)
            .sheet(isPresented: $manager.showsPreview) {
                ProjectChangePreview(manager: manager)
            }
            .sheet(isPresented: $manager.showsRulePreview) {
                RuleChangePreview(manager: manager)
            }
            .sheet(item: $selectedSourceSkill) { skill in
                if manager.isGlobalSync,
                   skillManager.skills.contains(where: { $0.id == skill.name && $0.canonicalURL.standardizedFileURL == skill.sourceURL.standardizedFileURL }) {
                    SkillDetailView(
                        skillID: skill.name,
                        viewModel: SkillDetailViewModel(skillManager: skillManager)
                    )
                    .frame(minWidth: 760, minHeight: 620)
                } else {
                    ProjectSkillDetailView(row: skill)
                        .frame(minWidth: 680, minHeight: 560)
                }
            }
        } else {
            ContentUnavailableView("选择项目", systemImage: "folder", description: Text("在中间列表中选择一个项目，查看它的技能同步状态。"))
        }
    }

    private func projectHeader(_ project: ManagedProject) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(project.name).appFont(.title2).fontWeight(.bold)
            Text(project.rootURL.tildeAbbreviatedPath).appFont(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text("源：\(project.sourceSkillsURL.tildeAbbreviatedPath)").appFont(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
        }
        .padding()
    }

    /// Rule controls are source-level actions: selecting a single skills target must not change
    /// which project rules are created, backed up, or removed.
    private func rulesSection(_ project: ManagedProject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("统一规则", systemImage: "doc.text")
                    .appFont(.headline)
                Spacer()
                Text("\(manager.linkedRuleCount)/\(manager.selectedRuleInspections.count) 已同步")
                    .appFont(.caption)
                    .foregroundStyle(manager.linkedRuleCount == manager.selectedRuleInspections.count && manager.hasSelectedRulesSource ? .green : .secondary)
            }
            if let sourceURL = manager.selectedRulesSourceURL {
                Text(sourceURL.tildeAbbreviatedPath)
                    .appFont(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                if manager.hasSelectedRulesSource, let sourceURL = manager.selectedRulesSourceURL {
                    Button {
                        NSWorkspace.shared.open(sourceURL)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .help("编辑统一规则")

                    Button("同步全部规则") { manager.previewRuleSyncAll() }
                        .buttonStyle(.borderedProminent)
                    Button("移除规则链接", role: .destructive) { manager.previewRuleRemoval() }
                        .disabled(manager.linkedRuleCount == 0)
                } else {
                    Button("新建统一规则") { manager.createRulesSource() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
    }

    private func agentRail(_ project: ManagedProject) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(manager.targets) { agent in
                    let targetInspection = manager.inspection(projectID: project.id, targetID: agent.id)
                    let isSelected = manager.selectedTargetID == agent.id
                    Button {
                        manager.select(project: project.id, target: agent.id)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: targetInspection?.isWholeDirectorySynced == true ? "checkmark.circle.fill" : "circle")
                            Text(agent.name)
                            Text(targetInspection.map { $0.isWholeDirectorySynced ? "\($0.skills.count)/\($0.skills.count)" : "0/\($0.skills.count)" } ?? "-")
                                .monospacedDigit()
                        }
                        .appFont(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .foregroundStyle(isSelected ? .white : .primary)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(agent.relativeSkillsPath)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func skillsContent(_ inspection: ProjectInspection) -> some View {
        if !inspection.targetIsAvailable {
            ContentUnavailableView(
                "未检测到项目源技能",
                systemImage: "folder.badge.questionmark",
                description: Text("在项目 .agents/skills 下添加包含 SKILL.md 的技能后即可整体同步。")
            )
        } else if inspection.skills.isEmpty {
            ContentUnavailableView(
                "没有项目技能",
                systemImage: "square.stack.3d.up",
                description: Text("在项目 .agents/skills 下添加包含 SKILL.md 的技能。")
            )
        } else {
            List(inspection.skills) { skill in
                Button {
                    selectedSourceSkill = skill
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "puzzlepiece.extension")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(skill.name).appFont(.headline)
                            Text(manager.isGlobalSync ? "全局源技能，点击查看和更新" : "项目技能，点击查看和更新")
                                .appFont(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if !manager.isGlobalSync {
                            Image(systemName: "arrow.up.circle")
                                .foregroundStyle(.secondary)
                                .help("查看和更新项目技能")
                        }
                        Image(systemName: "chevron.right")
                            .appFont(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private func actionBar(_ inspection: ProjectInspection) -> some View {
        HStack {
            Button("同步全部工具") { manager.previewSyncAll() }
                .buttonStyle(.borderedProminent)
            Button("同步整个 skills 目录") { manager.previewSync() }
            Button("移除同步目录链接", role: .destructive) { manager.previewRemoval() }
                .disabled(!manager.canRemoveSelectedTarget)
            Spacer()
            Text("源技能 \(inspection.skills.count) 项")
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

private struct ProjectChangePreview: View {
    @Bindable var manager: ProjectManager
    @Environment(\.dismiss) private var dismiss

    private var sourcePath: String {
        manager.changes.first?.sourceRoot.tildeAbbreviatedPath ?? "-"
    }

    private var primaryActionLabel: String {
        if manager.changes.count > 1 {
            return manager.changes.contains(where: \.needsResolution)
                ? "备份后同步 \(manager.changes.count) 个工具"
                : "同步 \(manager.changes.count) 个工具"
        }
        return switch manager.changes.first?.kind {
        case .replaceDirectory: "备份后整体替换"
        case .removeDirectoryLink: "移除目录软链"
        case .createDirectoryLink, nil: "创建目录软链"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // This header matches the app's existing import sheets: compact title, close control, and a divider.
            HStack {
                Text("项目同步变更").appFont(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            .padding()

            Divider()

            Text("同步会将每个目标 skills 目录指向：\(sourcePath)")
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top])

            if !manager.changes.isEmpty {
                List(manager.changes) { change in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(change.kind.label)：\(change.targetRoot.tildeAbbreviatedPath)")
                            .appFont(.headline)
                        Text("包含 \(change.skillNames.count) 个源技能")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                        Text(change.summary).appFont(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            Divider()

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button(primaryActionLabel) {
                    manager.applyChanges(replacingExistingDirectory: manager.changes.contains(where: \.needsResolution))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 560, idealWidth: 680, maxWidth: 820, minHeight: 320, maxHeight: 620)
        .alert("同步失败", isPresented: Binding(
            get: { manager.applyErrorMessage != nil },
            set: { if !$0 { manager.applyErrorMessage = nil } }
        )) {
            Button("好", role: .cancel) {
                manager.applyErrorMessage = nil
            }
        } message: {
            Text(manager.applyErrorMessage ?? "")
        }
        .alert("同步结果", isPresented: Binding(
            get: { manager.applyResultMessage != nil },
            set: { if !$0 { manager.applyResultMessage = nil } }
        )) {
            Button("完成") {
                manager.finishApplyingChanges()
                dismiss()
            }
        } message: {
            Text(manager.applyResultMessage ?? "")
        }
    }
}

/// RuleChangePreview mirrors the skills confirmation dialog but lists files, not directories.
/// Existing rules remain untouched until the single destructive confirmation is selected.
private struct RuleChangePreview: View {
    @Bindable var manager: ProjectManager
    @Environment(\.dismiss) private var dismiss

    private var primaryActionLabel: String {
        if manager.ruleChanges.contains(where: \.needsResolution) {
            return "备份后同步 \(manager.ruleChanges.count) 条规则"
        }
        return manager.ruleChanges.first?.kind == .removeLink
            ? "移除 \(manager.ruleChanges.count) 条规则链接"
            : "同步 \(manager.ruleChanges.count) 条规则"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("统一规则变更").appFont(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            .padding()

            Divider()

            Text("所有目标规则将引用同一份 AGENTS.md；Cursor 使用可识别的 .mdc 包装规则。")
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top])

            List(manager.ruleChanges) { change in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(change.kind.label)：\(change.target.name)")
                        .appFont(.headline)
                    Text(change.targetURL.tildeAbbreviatedPath)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    Text(change.summary)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider()

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button(primaryActionLabel) {
                    manager.applyRuleChanges(replacingExistingRules: manager.ruleChanges.contains(where: \.needsResolution))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 560, idealWidth: 680, maxWidth: 820, minHeight: 320, maxHeight: 620)
        .alert("规则同步失败", isPresented: Binding(
            get: { manager.ruleApplyErrorMessage != nil },
            set: { if !$0 { manager.ruleApplyErrorMessage = nil } }
        )) {
            Button("好", role: .cancel) { manager.ruleApplyErrorMessage = nil }
        } message: {
            Text(manager.ruleApplyErrorMessage ?? "")
        }
        .alert("规则同步结果", isPresented: Binding(
            get: { manager.ruleApplyResultMessage != nil },
            set: { if !$0 { manager.ruleApplyResultMessage = nil } }
        )) {
            Button("完成") {
                manager.finishApplyingRuleChanges()
                dismiss()
            }
        } message: {
            Text(manager.ruleApplyResultMessage ?? "")
        }
    }
}
