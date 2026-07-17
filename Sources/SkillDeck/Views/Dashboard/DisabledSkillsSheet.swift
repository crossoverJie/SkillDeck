import SwiftUI

/// DisabledSkillsSheet provides the user-facing recovery path for skills archived outside projects.
/// A sheet keeps disabled items separate from active dashboard rows, so archived skills cannot be
/// mistaken for currently available skills while still remaining one click away to restore.
struct DisabledSkillsSheet: View {
    @Bindable var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.disabledSkills.isEmpty {
                    ContentUnavailableView("没有已禁用技能", systemImage: "archivebox")
                } else {
                    List(viewModel.disabledSkills) { record in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.displayName).appFont(.headline)
                                Text(record.projectName ?? record.scopeLabel)
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                                Text(NSString(string: record.originalPath).abbreviatingWithTildeInPath)
                                    .appFont(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("恢复") {
                                Task { await viewModel.restoreDisabledSkill(record) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .navigationTitle("已禁用技能")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 320)
        .task { viewModel.reloadDisabledSkills() }
    }
}
