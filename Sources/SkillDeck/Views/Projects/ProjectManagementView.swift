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
                    L10n.currentString(L10nKeys.projectsEmptyTitle),
                    systemImage: "folder.badge.plus",
                    description: Text(L10n.currentString(L10nKeys.projectsEmptyDescription))
                )
            } else {
                List(manager.projects, selection: $manager.selectedProjectID) { project in
                    ProjectRow(project: project, manager: manager)
                        .tag(Optional(project.id))
                        .contextMenu {
                            Button(L10n.currentString(L10nKeys.commonShowInFinder)) {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.rootPath)
                            }
                            Divider()
                            Button(L10n.currentString(L10nKeys.projectsRemove), role: .destructive) {
                                manager.remove(projectID: project.id)
                            }
                        }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .navigationTitle(L10n.currentString(L10nKeys.projectsTitle))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: chooseProject) {
                    Image(systemName: "plus")
                }
                .help(L10n.currentString(L10nKeys.projectsAdd))
            }
            ToolbarItem {
                Button { manager.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help(L10n.currentString(L10nKeys.projectsRescan))
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
        panel.message = L10n.currentString(L10nKeys.projectsChooseRoot)
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
                Text(L10n.currentFormat(L10nKeys.projectsSkillCount, sourceCount))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(project.rootURL.tildeAbbreviatedPath)
                .appFont(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Label(L10n.currentFormat(L10nKeys.projectsSyncedToolsCount, fullySyncedTargets, manager.targets.count), systemImage: "link")
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
            ContentUnavailableView(L10n.currentString(L10nKeys.projectsSelectTitle), systemImage: "folder", description: Text(L10n.currentString(L10nKeys.projectsSelectDescription)))
        }
    }

    private func projectHeader(_ project: ManagedProject) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(project.name).appFont(.title2).fontWeight(.bold)
            Text(project.rootURL.tildeAbbreviatedPath).appFont(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text(L10n.currentFormat(L10nKeys.commonSourcePath, project.sourceSkillsURL.tildeAbbreviatedPath)).appFont(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
        }
        .padding()
    }

    /// Rule controls are source-level actions: selecting a single skills target must not change
    /// which project rules are created, backed up, or removed.
    private func rulesSection(_ project: ManagedProject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L10n.currentString(L10nKeys.projectsRulesTitle), systemImage: "doc.text")
                    .appFont(.headline)
                Spacer()
                Text(L10n.currentFormat(L10nKeys.projectsRulesSyncedCount, manager.linkedRuleCount, manager.selectedRuleInspections.count))
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
                    .help(L10n.currentString(L10nKeys.projectsRulesEdit))

                    Button(L10n.currentString(L10nKeys.projectsRulesSyncAll)) { manager.previewRuleSyncAll() }
                        .buttonStyle(.borderedProminent)
                    Button(L10n.currentString(L10nKeys.projectsRulesRemove), role: .destructive) { manager.previewRuleRemoval() }
                        .disabled(manager.linkedRuleCount == 0)
                } else {
                    Button(L10n.currentString(L10nKeys.projectsRulesCreate)) { manager.createRulesSource() }
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
                L10n.currentString(L10nKeys.projectsSkillsMissingTitle),
                systemImage: "folder.badge.questionmark",
                description: Text(L10n.currentString(L10nKeys.projectsSkillsMissingDescription))
            )
        } else if inspection.skills.isEmpty {
            ContentUnavailableView(
                L10n.currentString(L10nKeys.projectsSkillsEmptyTitle),
                systemImage: "square.stack.3d.up",
                description: Text(L10n.currentString(L10nKeys.projectsSkillsEmptyDescription))
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
                            Text(L10n.currentString(manager.isGlobalSync ? L10nKeys.projectsSkillDetailGlobal : L10nKeys.projectsSkillDetailProject))
                                .appFont(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if !manager.isGlobalSync {
                            Image(systemName: "arrow.up.circle")
                                .foregroundStyle(.secondary)
                                .help(L10n.currentString(L10nKeys.projectsSkillDetailHelp))
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
            Button(L10n.currentString(L10nKeys.projectsSyncAllTools)) { manager.previewSyncAll() }
                .buttonStyle(.borderedProminent)
            Button(L10n.currentString(L10nKeys.projectsSyncDirectory)) { manager.previewSync() }
            Button(L10n.currentString(L10nKeys.projectsRemoveDirectory), role: .destructive) { manager.previewRemoval() }
                .disabled(!manager.canRemoveSelectedTarget)
            Spacer()
            Text(L10n.currentFormat(L10nKeys.projectsSourceSkillCount, inspection.skills.count))
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
                ? L10n.currentFormat(L10nKeys.syncActionBackupAll, manager.changes.count)
                : L10n.currentFormat(L10nKeys.syncActionAll, manager.changes.count)
        }
        return switch manager.changes.first?.kind {
        case .replaceDirectory: L10n.currentString(L10nKeys.syncActionBackupReplace)
        case .removeDirectoryLink: L10n.currentString(L10nKeys.syncActionRemoveLink)
        case .createDirectoryLink, nil: L10n.currentString(L10nKeys.syncActionCreateLink)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // This header matches the app's existing import sheets: compact title, close control, and a divider.
            HStack {
                Text(L10n.currentString(L10nKeys.projectsChangeTitle)).appFont(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.currentString(L10nKeys.commonClose))
            }
            .padding()

            Divider()

            Text(L10n.currentFormat(L10nKeys.projectsChangeDestination, sourcePath))
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top])

            if !manager.changes.isEmpty {
                List(manager.changes) { change in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(change.kind.label)：\(change.targetRoot.tildeAbbreviatedPath)")
                            .appFont(.headline)
                        Text(L10n.currentFormat(L10nKeys.projectsChangeContainsSkills, change.skillNames.count))
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
                Button(L10n.currentString(L10nKeys.commonCancel)) { dismiss() }
                Spacer()
                Button(primaryActionLabel) {
                    manager.applyChanges(replacingExistingDirectory: manager.changes.contains(where: \.needsResolution))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 560, idealWidth: 680, maxWidth: 820, minHeight: 320, maxHeight: 620)
        .alert(L10n.currentString(L10nKeys.projectsSyncFailed), isPresented: Binding(
            get: { manager.applyErrorMessage != nil },
            set: { if !$0 { manager.applyErrorMessage = nil } }
        )) {
            Button(L10n.currentString(L10nKeys.commonOK), role: .cancel) {
                manager.applyErrorMessage = nil
            }
        } message: {
            Text(manager.applyErrorMessage ?? "")
        }
        .alert(L10n.currentString(L10nKeys.projectsSyncResult), isPresented: Binding(
            get: { manager.applyResultMessage != nil },
            set: { if !$0 { manager.applyResultMessage = nil } }
        )) {
            Button(L10n.currentString(L10nKeys.commonDone)) {
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
            return L10n.currentFormat(L10nKeys.ruleActionBackup, manager.ruleChanges.count)
        }
        return manager.ruleChanges.first?.kind == .removeLink
            ? L10n.currentFormat(L10nKeys.ruleActionRemove, manager.ruleChanges.count)
            : L10n.currentFormat(L10nKeys.ruleActionSync, manager.ruleChanges.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.currentString(L10nKeys.projectsRulesChangeTitle)).appFont(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.currentString(L10nKeys.commonClose))
            }
            .padding()

            Divider()

            Text(L10n.currentString(L10nKeys.projectsRulesChangeDescription))
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
                Button(L10n.currentString(L10nKeys.commonCancel)) { dismiss() }
                Spacer()
                Button(primaryActionLabel) {
                    manager.applyRuleChanges(replacingExistingRules: manager.ruleChanges.contains(where: \.needsResolution))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 560, idealWidth: 680, maxWidth: 820, minHeight: 320, maxHeight: 620)
        .alert(L10n.currentString(L10nKeys.projectsRulesFailed), isPresented: Binding(
            get: { manager.ruleApplyErrorMessage != nil },
            set: { if !$0 { manager.ruleApplyErrorMessage = nil } }
        )) {
            Button(L10n.currentString(L10nKeys.commonOK), role: .cancel) { manager.ruleApplyErrorMessage = nil }
        } message: {
            Text(manager.ruleApplyErrorMessage ?? "")
        }
        .alert(L10n.currentString(L10nKeys.projectsRulesResult), isPresented: Binding(
            get: { manager.ruleApplyResultMessage != nil },
            set: { if !$0 { manager.ruleApplyResultMessage = nil } }
        )) {
            Button(L10n.currentString(L10nKeys.commonDone)) {
                manager.finishApplyingRuleChanges()
                dismiss()
            }
        } message: {
            Text(manager.ruleApplyResultMessage ?? "")
        }
    }
}
