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
                    Text("\(sourceSkillCount) 个技能")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(source.sourceSkillsURL.tildeAbbreviatedPath)
                    .appFont(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Label("\(syncedTargetCount)/\(manager.targets.count) 个工具已整体同步", systemImage: "link")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .tag(Optional(source.id))
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .navigationTitle("全局同步")
        .toolbar {
            ToolbarItem {
                Button { manager.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help("重新扫描全局技能")
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
