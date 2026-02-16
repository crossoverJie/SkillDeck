import SwiftUI

/// Sidebar navigation item enum
///
/// Each case represents a clickable item in the sidebar.
/// F09 adds `.registry` for browsing the skills.sh catalog.
enum SidebarItem: Hashable {
    case dashboard
    /// F09: Browse skills.sh catalog (leaderboard + search)
    case registry
    case agent(AgentType)
    case settings

    /// Maps sidebar options to Agent filter values
    /// - .dashboard / .settings / .registry → nil (show all skills or different content)
    /// - .agent(type) → type (only show skills for this Agent)
    /// This computed property is similar to Java's getter, executes switch calculation on each access
    var agentFilter: AgentType? {
        switch self {
        case .agent(let agentType):
            return agentType
        case .dashboard, .settings, .registry:
            return nil
        }
    }
}

/// SidebarView is the app's sidebar navigation
///
/// macOS sidebar visual guidelines (referencing Finder, Mail and other native apps):
/// - Selected: rounded rectangle with accentColor semi-transparent background
/// - Hover: very light gray background, hinting it's clickable
/// - Normal: transparent background
///
/// @Binding is two-way binding (similar to Vue's v-model), parent and child components share the same state
struct SidebarView: View {

    @Binding var selection: SidebarItem?
    @Environment(SkillManager.self) private var skillManager

    /// macOS 14+ provides native SwiftUI action to open settings window
    /// @Environment(\.openSettings) gets the system-provided OpenSettingsAction from environment,
    /// calling openSettings() is equivalent to user pressing Cmd+, (more reliable than NSApp.sendAction)
    @Environment(\.openSettings) private var openSettings

    /// Currently hovered sidebar item
    /// @State is view-private state, hover state is only used within this view, no need to pass to parent component
    @State private var hoveredItem: SidebarItem?

    /// F10: Install modal's ViewModel (created only when showing sheet)
    /// Uses `.sheet(item:)` binding: shows sheet when non-nil, closes when nil
    /// This way uses only one @State variable to control both sheet display and content, avoiding dual state synchronization timing issues
    @State private var installVM: SkillInstallViewModel?

    var body: some View {
        List(selection: $selection) {
            // Section creates groups (shown as collapsible groups in macOS sidebar)
            Section("Overview") {
                sidebarRow(item: .dashboard) {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                }
                .badge(skillManager.skills.count)

                // F09: Registry browser — browse and search skills.sh catalog
                sidebarRow(item: .registry) {
                    Label("Registry", systemImage: "globe")
                }
            }

            Section("Agents") {
                ForEach(AgentType.allCases) { agentType in
                    let agent = skillManager.agents.first { $0.type == agentType }

                    sidebarRow(item: .agent(agentType)) {
                        Label {
                            Text(agentType.displayName)
                        } icon: {
                            Image(systemName: agentType.iconName)
                                .foregroundStyle(Constants.AgentColors.color(for: agentType))
                        }
                    }
                    .badge(skillManager.skills(for: agentType).count)
                    // Use skillManager.skills(for:) instead of agent?.skillCount,
                    // because the latter only counts skills in Agent's own directory (from AgentDetector),
                    // not including inherited installations (like Copilot inheriting skills from Claude directory)
                    // opacity controls transparency: uninstalled Agents are shown semi-transparent
                    .opacity(agent?.isInstalled == true ? 1.0 : 0.5)
                }
            }
        }
        // macOS sidebar standard style
        .listStyle(.sidebar)
        .navigationTitle("SkillDeck")
        // Sidebar top toolbar action buttons (native macOS toolbar style)
        // Works with .navigationSplitViewColumnWidth(min: 180) minimum width constraint in ContentView,
        // ensures sidebar won't be too narrow when window state is restored, preventing ToolbarItem overflow/hiding
        .toolbar {
            // App update reminder button: shows orange upward arrow when new version is available
            // Opens settings window when clicked (by sending system notification showSettingsWindow)
            // Only shows when appUpdateInfo is not nil, users will notice this newly appearing icon
            ToolbarItem {
                if skillManager.appUpdateInfo != nil {
                    Button {
                        // openSettings() is macOS 14+ native SwiftUI API,
                        // equivalent to user pressing Cmd+, opens settings window defined in Settings { } scene
                        openSettings()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    .help("Update available! Click to open settings.")
                }
            }

            // F10: "+" button for installing new skill
            // ToolbarItem defaults to toolbar trailing when placement is not specified
            ToolbarItem {
                Button {
                    installVM = SkillInstallViewModel(skillManager: skillManager)
                } label: {
                    Image(systemName: "plus")
                }
                .help("Install skill from GitHub")
            }

            // F12: Batch check updates for all skills
            ToolbarItem {
                Button {
                    Task { await skillManager.checkAllUpdates() }
                } label: {
                    // When checking, shows spinning progress indicator (ProgressView) + progress count (e.g., 3/12),
                    // otherwise shows static icon
                    if skillManager.isCheckingUpdates {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                            // Progress count: counts number of skills that have completed checking / total pending check count
                            // Skills in .checking state are still being checked, others (.hasUpdate/.upToDate/.error) indicate completed
                            let total = skillManager.skills.filter { $0.lockEntry != nil }.count
                            // compactMap is similar to Java Stream's filter+map combination:
                            // first get value from dictionary (may be nil), then filter out .checking state
                            let checked = skillManager.updateStatuses.values.filter {
                                $0 != .checking && $0 != .notChecked
                            }.count
                            Text("\(checked)/\(total)")
                                .font(.caption)
                                .monospacedDigit()  // Monospaced digit font, avoids width jumping when numbers change
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .help("Check all skills for updates")
                .disabled(skillManager.isCheckingUpdates)
            }

            // Refresh button: rescan file system
            ToolbarItem {
                Button {
                    Task { await skillManager.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh skills")
            }
        }
        // F10: Install sheet modal
        // .sheet(item:) binds sheet display and content to the same Optional variable:
        // - installVM non-nil → show sheet, closure parameter vm is the unwrapped value
        // - installVM nil → close sheet
        // This is safer than .sheet(isPresented:) + extra @State, avoids dual state sync timing causing blank window on first open
        // onDismiss calls cleanup to clean temp directory when sheet closes
        .sheet(item: $installVM, onDismiss: {
            installVM?.cleanup()
            installVM = nil
        }) { vm in
            SkillInstallView(viewModel: vm)
                // .environment() injects SkillManager into sheet's view tree
                // Sheet creates new view hierarchy, needs to re-inject environment dependencies
                .environment(skillManager)
        }
    }

    /// Build sidebar row view,统一 handling click, selection highlight and hover effects
    ///
    /// @ViewBuilder allows closure to return different View types (similar to Java's generic methods)
    /// `some View` is Swift's opaque return type,
    /// means "returns some View, but caller doesn't need to know the specific type"
    @ViewBuilder
    private func sidebarRow<Label: View>(
        item: SidebarItem,
        @ViewBuilder label: () -> Label
    ) -> some View {
        // Button ensures clicking always updates selection (List native selection is unreliable in some macOS versions)
        Button { selection = item } label: { label() }
            // .buttonStyle(.plain) removes button default styles (border, press effect, etc.)
            .buttonStyle(.plain)
            // .contentShape(Rectangle()) expands interaction area (click+hover) to entire row rectangle
            // By default Button only responds to events in content (text/icon) area,
            // row's blank area doesn't trigger .onHover, causing hover effect to only appear above text
            // Similar to CSS pointer-events: all + width: 100%
            .contentShape(Rectangle())
            // .tag 关联选中值，让 List 知道这一行对应哪个 SidebarItem
            .tag(item)
            // .onHover listens for mouse enter/leave events (macOS specific, similar to CSS :hover)
            // Closure parameter isHovering: Bool indicates if mouse is over element
            .onHover { isHovering in
                // Use withAnimation to add transition animation, .easeInOut is ease-in-out curve
                // duration: 0.15 is 150 milliseconds, fast enough but not abrupt
                withAnimation(.easeInOut(duration: 0.15)) {
                    hoveredItem = isHovering ? item : nil
                }
            }
            // .listRowBackground customizes list row background (overrides List's default selection/hover styles)
            // Here uses RoundedRectangle to draw rounded rectangle, simulating macOS native sidebar selection/hover effects
            .listRowBackground(
                RoundedRectangle(cornerRadius: 6)
                    .fill(rowBackground(for: item))
            )
    }

    /// Returns row background color based on selection/hover state
    /// macOS native sidebar color guidelines:
    /// - Selected: accentColor (system accent color, default blue) + low opacity
    /// - Hover: primary (adaptive black/white) + very low opacity
    /// - Normal: fully transparent
    private func rowBackground(for item: SidebarItem) -> Color {
        if selection == item {
            // Selected state: if Agent item, use that Agent's brand color; Dashboard/Settings keep system accentColor
            // Swift 5.9 if/else expression syntax: can use if-else directly in let assignment, similar to ternary but supports pattern matching
            let baseColor: Color = if case .agent(let agentType) = item {
                Constants.AgentColors.color(for: agentType)
            } else {
                Color.accentColor
            }
            return baseColor.opacity(0.15)
        } else if hoveredItem == item {
            // Hover state: very light gray background, hinting "this is clickable"
            return Color.primary.opacity(0.08)
        }
        // Normal state: transparent
        return Color.clear
    }
}
