import Foundation
import Observation

/// A user-selected project root. Projects are never discovered recursively.
struct ManagedProject: Codable, Hashable, Identifiable {
    let rootPath: String
    let displayName: String?
    /// Optional preserves UserDefaults records written before the global-source flag existed.
    let usesConfiguredGlobalSource: Bool?

    init(rootPath: String, displayName: String? = nil, usesConfiguredGlobalSource: Bool = false) {
        self.rootPath = rootPath
        self.displayName = displayName
        self.usesConfiguredGlobalSource = usesConfiguredGlobalSource
    }

    var id: String { rootPath }
    var rootURL: URL { URL(fileURLWithPath: rootPath) }
    var name: String { displayName ?? rootURL.lastPathComponent }
    var sourceSkillsURL: URL {
        usesConfiguredGlobalSource == true ? SkillStorageSettings.globalSkillsURL : rootURL.appendingPathComponent(".agents/skills")
    }
}

/// Project-local agent directories. These paths intentionally differ from AgentType, which models
/// paths under the user home directory.
struct ProjectAgent: Hashable, Identifiable {
    let id: String
    let name: String
    let relativeSkillsPath: String
    let createsSkillsDirectoryWhenMissing: Bool
    /// Global synchronization resolves the path from AgentType so custom tool settings apply.
    let globalAgentType: AgentType?

    init(
        id: String,
        name: String,
        relativeSkillsPath: String,
        createsSkillsDirectoryWhenMissing: Bool,
        globalAgentType: AgentType? = nil
    ) {
        self.id = id
        self.name = name
        self.relativeSkillsPath = relativeSkillsPath
        self.createsSkillsDirectoryWhenMissing = createsSkillsDirectoryWhenMissing
        self.globalAgentType = globalAgentType
    }

    func skillsURL(in project: ManagedProject) -> URL {
        if project.usesConfiguredGlobalSource == true, let globalAgentType {
            return globalAgentType.skillsDirectoryURL
        }
        return project.rootURL.appendingPathComponent(relativeSkillsPath)
    }

    /// One complete tool registry drives the sidebar, project synchronization, and global synchronization.
    /// Project targets use their relative configuration paths; global targets use each tool's configured path.
    static let all: [ProjectAgent] = AgentType.allCases.map { agent in
        .init(
            id: agent.id,
            name: agent.displayName,
            relativeSkillsPath: agent.projectSkillsRelativePath,
            createsSkillsDirectoryWhenMissing: true,
            globalAgentType: agent
        )
    }

    /// The global synchronization screen uses the same complete registry as project synchronization.
    static let global: [ProjectAgent] = AgentType.allCases.map { agent in
        .init(
            id: agent.id,
            name: agent.displayName,
            relativeSkillsPath: agent.projectSkillsRelativePath,
            createsSkillsDirectoryWhenMissing: true,
            globalAgentType: agent
        )
    }
}

enum ProjectSkillState: String {
    case linked, directoryLinked, missing, broken, foreignLink, occupied, rootConflict

    var label: String {
        switch self {
        case .linked: "已同步"
        case .directoryLinked: "整目录已同步"
        case .missing: "未同步"
        case .broken: "失效软链"
        case .foreignLink: "指向其他位置"
        case .occupied: "已有真实文件"
        case .rootConflict: "目标目录冲突"
        }
    }

    var isLinked: Bool { self == .linked || self == .directoryLinked }
}

struct ProjectSkillRow: Identifiable, Hashable {
    let name: String
    let sourceURL: URL
    let targetURL: URL
    let state: ProjectSkillState
    let detail: String

    var id: String { targetURL.path }
}

/// Represents one canonical project skill in dashboard context. Project inspections contain one
/// copy per AI tool target, so this wrapper keeps the project identity while exposing a single
/// source directory to the dashboard.
struct ProjectDashboardSkill: Identifiable {
    let project: ManagedProject
    let row: ProjectSkillRow

    /// Absolute source paths remain unique when separate projects use the same skill folder name.
    var id: String { row.sourceURL.standardizedFileURL.path }
}

struct ProjectInspection: Identifiable {
    let project: ManagedProject
    let agent: ProjectAgent
    let targetRootIsDirectoryLink: Bool
    let targetIsAvailable: Bool
    let skills: [ProjectSkillRow]

    var id: String { project.id + "|" + agent.id }
    var targetURL: URL { agent.skillsURL(in: project) }
    var isWholeDirectorySynced: Bool {
        targetRootIsDirectoryLink && !skills.isEmpty && skills.allSatisfy { $0.state == .directoryLinked }
    }
}

enum ProjectChangeKind: String {
    case createDirectoryLink, replaceDirectory, removeDirectoryLink
    var label: String {
        switch self {
        case .createDirectoryLink: "创建目录软链"
        case .replaceDirectory: "备份后整体替换"
        case .removeDirectoryLink: "移除目录软链"
        }
    }
}

enum ProjectConflictResolution: String, CaseIterable, Identifiable {
    case skip, backupAndReplace
    var id: String { rawValue }
    var label: String { self == .skip ? "跳过" : "备份后替换" }
}

struct ProjectChange: Identifiable {
    let id = UUID()
    let kind: ProjectChangeKind
    let sourceRoot: URL
    let targetRoot: URL
    let skillNames: [String]
    let summary: String
    let needsResolution: Bool
    var resolution: ProjectConflictResolution = .skip
}

/// ProjectSyncFileSystem is pure filesystem logic that can also be exercised with temporary folders.
struct ProjectSyncFileSystem {
    let fileManager: FileManager
    let backupRoot: URL

    init(fileManager: FileManager = .default, backupRoot: URL? = nil) {
        self.fileManager = fileManager
        self.backupRoot = backupRoot ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SkillDeck/ProjectSyncBackups", isDirectory: true)
    }

    func inspect(project: ManagedProject, agent: ProjectAgent) -> ProjectInspection {
        let source = project.sourceSkillsURL
        guard fileManager.fileExists(atPath: source.path) else {
            return ProjectInspection(project: project, agent: agent, targetRootIsDirectoryLink: false, targetIsAvailable: false, skills: [])
        }
        let target = agent.skillsURL(in: project)
        let rootLink = linkDestination(at: target)
        let rootLinksSource = rootLink.map { sameLocation($0, source) } ?? false
        let available = fileManager.fileExists(atPath: target.path) || agent.createsSkillsDirectoryWhenMissing || rootLink != nil
        let names = (try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
        let skills = names.compactMap { sourceItem -> ProjectSkillRow? in
            let canonical = sourceItem.resolvingSymlinksInPath()
            guard fileManager.fileExists(atPath: canonical.appendingPathComponent("SKILL.md").path) else { return nil }
            let targetItem = target.appendingPathComponent(sourceItem.lastPathComponent)
            let state: ProjectSkillState
            let detail: String
            if rootLinksSource {
                state = .directoryLinked
                detail = target.path
            } else if rootLink != nil {
                state = .rootConflict
                detail = rootLink!.path
            } else if let destination = linkDestination(at: targetItem) {
                if sameLocation(destination, sourceItem) { state = .linked } else if fileManager.fileExists(atPath: targetItem.path) { state = .foreignLink } else { state = .broken }
                detail = destination.path
            } else if fileManager.fileExists(atPath: targetItem.path) {
                state = .occupied
                detail = targetItem.path
            } else {
                state = .missing
                detail = targetItem.path
            }
            return ProjectSkillRow(name: sourceItem.lastPathComponent, sourceURL: sourceItem, targetURL: targetItem, state: state, detail: detail)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return ProjectInspection(project: project, agent: agent, targetRootIsDirectoryLink: rootLink != nil, targetIsAvailable: available, skills: skills)
    }

    /// Project sync always migrates the entire source skills directory to one target directory link.
    /// Per-skill plans are intentionally unsupported because they create a second, inconsistent sync model.
    func syncPlan(for inspection: ProjectInspection) -> [ProjectChange] {
        guard inspection.targetIsAvailable, !inspection.skills.isEmpty else { return [] }
        let source = inspection.project.sourceSkillsURL
        let target = inspection.targetURL
        let skillNames = inspection.skills.map(\.name)
        if sameLocation(linkDestination(at: target) ?? target, source) { return [] }
        if fileManager.fileExists(atPath: target.path) || linkDestination(at: target) != nil {
            return [.init(kind: .replaceDirectory, sourceRoot: source, targetRoot: target, skillNames: skillNames, summary: "目标 skills 目录已有内容。备份后将整个目录改为直接指向项目 .agents/skills。", needsResolution: true)]
        }
        return [.init(kind: .createDirectoryLink, sourceRoot: source, targetRoot: target, skillNames: skillNames, summary: "创建整个 skills 目录软链，直接指向项目 .agents/skills。", needsResolution: false)]
    }

    /// Removal is only available for the full directory link owned by project sync.
    func removePlan(for inspection: ProjectInspection) -> [ProjectChange] {
        guard inspection.targetRootIsDirectoryLink,
              sameLocation(linkDestination(at: inspection.targetURL) ?? inspection.targetURL, inspection.project.sourceSkillsURL) else {
            return []
        }
        return [.init(kind: .removeDirectoryLink, sourceRoot: inspection.project.sourceSkillsURL, targetRoot: inspection.targetURL, skillNames: inspection.skills.map(\.name), summary: "只移除目标目录软链，不删除项目源技能。", needsResolution: false)]
    }

    func apply(_ change: ProjectChange) throws -> String {
        switch change.kind {
        case .createDirectoryLink:
            // The parent configuration folder may not exist yet for a known project agent.
            try fileManager.createDirectory(at: change.targetRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.createSymbolicLink(at: change.targetRoot, withDestinationURL: change.sourceRoot)
        case .replaceDirectory:
            guard change.resolution == .backupAndReplace else { return "保留目标 skills 目录" }
            let backup = try backup(change.targetRoot)
            try fileManager.createDirectory(at: change.targetRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.createSymbolicLink(at: change.targetRoot, withDestinationURL: change.sourceRoot)
            return "已备份到 \(backup.path)"
        case .removeDirectoryLink:
            try fileManager.removeItem(at: change.targetRoot)
        }
        return "已执行 \(change.kind.label)"
    }

    private func linkDestination(at url: URL) -> URL? {
        guard let value = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else { return nil }
        return URL(fileURLWithPath: value, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
    }

    private func sameLocation(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.resolvingSymlinksInPath().standardizedFileURL.path == rhs.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func backup(_ item: URL) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = backupRoot.appendingPathComponent(stamp, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(item.lastPathComponent + "-" + UUID().uuidString)
        try fileManager.moveItem(at: item, to: destination)
        return destination
    }
}

@MainActor
@Observable
final class ProjectManager {
    private static let storageKey = "SkillDeck.managedProjects"
    private let filesystem = ProjectSyncFileSystem()
    private let ruleFileSystem = RuleSyncFileSystem()
    private let fixedProject: ManagedProject?
    var projects: [ManagedProject] = []
    var inspections: [ProjectInspection] = []
    var selectedProjectID: String?
    var selectedTargetID: String?
    var changes: [ProjectChange] = []
    var showsPreview = false
    var applyErrorMessage: String?
    var applyResultMessage: String?
    var ruleInspections: [RuleInspection] = []
    var ruleChanges: [RuleChange] = []
    var showsRulePreview = false
    var ruleApplyErrorMessage: String?
    var ruleApplyResultMessage: String?
    var logs: [String] = []
    /// Changes whenever project filesystem inspection is refreshed, allowing dashboard data to reload.
    var dashboardRevision = 0

    /// Project-local targets and global AI tools intentionally use different path resolvers.
    /// The global set is the sidebar's AgentType list; projects retain their local configuration paths.
    var targets: [ProjectAgent] {
        fixedProject?.usesConfiguredGlobalSource == true ? ProjectAgent.global : ProjectAgent.all
    }

    /// Global sources are managed by SkillManager and can use its lock-file update workflow.
    var isGlobalSync: Bool { fixedProject?.usesConfiguredGlobalSource == true }

    /// A fixed project reuses the same whole-directory sync engine for the global ~/.agents source.
    init(fixedProject: ManagedProject? = nil) {
        self.fixedProject = fixedProject
        if let fixedProject {
            projects = [fixedProject]
        } else if let data = UserDefaults.standard.data(forKey: Self.storageKey), let saved = try? JSONDecoder().decode([ManagedProject].self, from: data) {
            projects = saved.filter { FileManager.default.fileExists(atPath: $0.rootPath) }
        }
        selectedProjectID = projects.first?.id
        selectedTargetID = targets.first?.id
    }

    var selectedInspection: ProjectInspection? { inspections.first { $0.project.id == selectedProjectID && $0.agent.id == selectedTargetID } }
    var canRemoveSelectedTarget: Bool {
        guard let inspection = selectedInspection else { return false }
        return !filesystem.removePlan(for: inspection).isEmpty
    }

    /// Used by project rows and the visible target rail without exposing filesystem implementation details.
    func inspection(projectID: String, targetID: String) -> ProjectInspection? {
        inspections.first { $0.project.id == projectID && $0.agent.id == targetID }
    }

    /// Rules are intentionally tracked per selected source, independent from the selected skills target.
    var selectedProject: ManagedProject? { projects.first { $0.id == selectedProjectID } }
    var selectedRulesSourceURL: URL? { selectedProject.map { ruleFileSystem.sourceURL(for: $0) } }
    var hasSelectedRulesSource: Bool { selectedProject.map { ruleFileSystem.sourceExists(for: $0) } ?? false }
    var selectedRuleInspections: [RuleInspection] { ruleInspections.filter { $0.project.id == selectedProjectID } }
    var linkedRuleCount: Int { selectedRuleInspections.filter { $0.state == .linked }.count }

    /// Source skills are repeated once per configured AI tool in `inspections`. The dashboard needs
    /// each project skill only once because opening or deleting it always acts on the source directory.
    var dashboardSkills: [ProjectDashboardSkill] {
        var seenSourcePaths = Set<String>()
        var skills: [ProjectDashboardSkill] = []
        for inspection in inspections {
            for row in inspection.skills {
                let sourcePath = row.sourceURL.standardizedFileURL.path
                guard seenSourcePaths.insert(sourcePath).inserted else { continue }
                skills.append(ProjectDashboardSkill(project: inspection.project, row: row))
            }
        }
        return skills
    }

    func addProject(_ url: URL) {
        guard fixedProject == nil else { return }
        let project = ManagedProject(rootPath: url.standardizedFileURL.path)
        guard !projects.contains(project) else { return }
        projects.append(project)
        projects.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        selectedProjectID = project.id
        selectedTargetID = targets.first?.id
        save(); reload(); log("已添加项目 \(project.rootPath)")
    }

    func removeSelectedProject() {
        guard fixedProject == nil else { return }
        guard let id = selectedProjectID else { return }
        projects.removeAll { $0.id == id }
        selectedProjectID = projects.first?.id
        save(); reload(); log("已移除项目 \(id)")
    }

    func remove(projectID: String) {
        selectedProjectID = projectID
        removeSelectedProject()
    }

    func reload() {
        inspections = projects.flatMap { project in targets.map { filesystem.inspect(project: project, agent: $0) } }
        ruleInspections = projects.flatMap { ruleFileSystem.inspect(project: $0) }
        dashboardRevision += 1
        log("已扫描 \(projects.count) 个项目")
    }

    func select(project: String?, target: String?) {
        selectedProjectID = project
        selectedTargetID = target
    }

    func previewSync() {
        guard let inspection = selectedInspection else { return }
        changes = filesystem.syncPlan(for: inspection)
        showsPreview = !changes.isEmpty
        log("同步预览 \(changes.count) 项")
    }

    /// Build one confirmation plan for every unsynchronized tool of the selected source.
    /// Each target remains a separate directory migration so conflicts can still be backed up safely.
    func previewSyncAll() {
        guard let projectID = selectedProjectID else { return }
        changes = inspections
            .filter { $0.project.id == projectID }
            .flatMap { filesystem.syncPlan(for: $0) }
        showsPreview = !changes.isEmpty
        log("全部同步预览 \(changes.count) 项")
    }
    func previewRemoval() { guard let inspection = selectedInspection else { return }; changes = filesystem.removePlan(for: inspection); showsPreview = !changes.isEmpty; log("移除预览 \(changes.count) 项") }

    /// Creates only the canonical source file. Target rule files are never generated until the user
    /// explicitly opens the rules preview and confirms synchronization.
    func createRulesSource() {
        guard let project = selectedProject else { return }
        do {
            try ruleFileSystem.createSource(for: project)
            reload()
            log("已创建统一规则源 \(ruleFileSystem.sourceURL(for: project).path)")
        } catch {
            ruleApplyErrorMessage = error.localizedDescription
        }
    }

    func previewRuleSyncAll() {
        guard let project = selectedProject else { return }
        ruleChanges = ruleFileSystem.syncPlan(for: project)
        showsRulePreview = !ruleChanges.isEmpty
        log("规则同步预览 \(ruleChanges.count) 项")
    }

    func previewRuleRemoval() {
        guard let project = selectedProject else { return }
        ruleChanges = ruleFileSystem.removePlan(for: project)
        showsRulePreview = !ruleChanges.isEmpty
        log("规则移除预览 \(ruleChanges.count) 项")
    }

    /// Applies the whole-directory migration after its explicit confirmation action.
    func applyChanges(replacingExistingDirectory: Bool = false) {
        applyErrorMessage = nil
        applyResultMessage = nil
        var failures: [String] = []
        var results: [String] = []

        for index in changes.indices where changes[index].needsResolution && replacingExistingDirectory {
            changes[index].resolution = .backupAndReplace
        }

        for change in changes {
            do {
                let result = try filesystem.apply(change)
                log(result)
                results.append(result)
            } catch {
                let message = error.localizedDescription
                log("失败：\(message)")
                failures.append(message)
            }
        }

        reload()

        guard failures.isEmpty else {
            applyErrorMessage = failures.joined(separator: "\n")
            return
        }

        applyResultMessage = results.joined(separator: "\n")
    }

    /// Clears the completed preview only after the user has seen the result message.
    func finishApplyingChanges() {
        changes = []
        showsPreview = false
        applyResultMessage = nil
    }

    func applyRuleChanges(replacingExistingRules: Bool = false) {
        ruleApplyErrorMessage = nil
        ruleApplyResultMessage = nil
        var failures: [String] = []
        var results: [String] = []

        for index in ruleChanges.indices where ruleChanges[index].needsResolution && replacingExistingRules {
            ruleChanges[index].resolution = .backupAndReplace
        }

        for change in ruleChanges {
            do {
                let result = try ruleFileSystem.apply(change)
                log("规则：\(result)")
                results.append(result)
            } catch {
                let message = error.localizedDescription
                log("规则失败：\(message)")
                failures.append(message)
            }
        }

        reload()
        if failures.isEmpty {
            ruleApplyResultMessage = results.joined(separator: "\n")
        } else {
            ruleApplyErrorMessage = failures.joined(separator: "\n")
        }
    }

    func finishApplyingRuleChanges() {
        ruleChanges = []
        showsRulePreview = false
        ruleApplyResultMessage = nil
    }

    private func save() {
        guard fixedProject == nil, let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
    private func log(_ message: String) { logs.insert("[项目同步] \(message)", at: 0); if logs.count > 100 { logs.removeLast() } }
}
