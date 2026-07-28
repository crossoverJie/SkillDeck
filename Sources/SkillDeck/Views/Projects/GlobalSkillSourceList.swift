import SwiftUI

/// GlobalSkillSourceList is the fixed source counterpart to ProjectTargetList.
/// It exposes the configured global skills directory as one source row, while ProjectSyncDetail manages
/// the same whole-directory migration workflow used by project-local skills.
struct GlobalSkillSourceList: View {
    @Bindable var manager: ProjectManager

    var body: some View {
        List(manager.projects, selection: $manager.selectedProjectID) { source in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(source.name, systemImage: "tray.full")
                        .appFont(.headline)
                    Spacer()
                    Text(L10n.currentFormat(L10nKeys.projectsSkillCount, sourceSkillCount))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(source.sourceSkillsURL.tildeAbbreviatedPath)
                    .appFont(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Label(L10n.currentFormat(L10nKeys.projectsSyncedToolsCount, syncedTargetCount, manager.targets.count), systemImage: "link")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .tag(Optional(source.id))
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .navigationTitle(L10n.currentString(L10nKeys.sidebarGlobalSync))
        .toolbar {
            ToolbarItem {
                Button { manager.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help(L10n.currentString(L10nKeys.globalSyncRescan))
            }
        }
        .onChange(of: manager.selectedProjectID) { _, projectID in
            manager.select(project: projectID, target: manager.selectedTargetID)
        }
        .onAppear { manager.reload() }
    }

    private var inspections: [ProjectInspection] {
        guard let sourceID = manager.selectedProjectID else { return [] }
        return manager.inspections.filter { $0.project.id == sourceID }
    }

    private var sourceSkillCount: Int {
        inspections.first?.skills.count ?? 0
    }

    private var syncedTargetCount: Int {
        inspections.filter(\.isWholeDirectorySynced).count
    }
}
