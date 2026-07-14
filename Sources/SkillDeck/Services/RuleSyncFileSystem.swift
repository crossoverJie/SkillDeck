import Foundation

/// Cursor needs a structured `.mdc` rule to appear in its Rules UI. Other supported targets can
/// consume a plain markdown file directly, so a symbolic link remains sufficient for them.
enum RuleTargetFormat: Equatable {
    case symbolicLink
    case cursorRule
}

/// RuleSyncTarget describes one documented rules entry point for a supported tool.
/// Project and global paths differ because project rules live beside source code while
/// global rules live in each tool's user configuration directory.
struct RuleSyncTarget: Identifiable, Hashable {
    let id: String
    let name: String
    let projectRelativePath: String
    let globalRelativePath: String
    let format: RuleTargetFormat

    init(
        id: String,
        name: String,
        projectRelativePath: String,
        globalRelativePath: String,
        format: RuleTargetFormat = .symbolicLink
    ) {
        self.id = id
        self.name = name
        self.projectRelativePath = projectRelativePath
        self.globalRelativePath = globalRelativePath
        self.format = format
    }

    /// Some documented rule locations exist only per repository, such as Copilot's `.github` file.
    var supportsGlobalSynchronization: Bool { !globalRelativePath.isEmpty }

    func url(in project: ManagedProject) -> URL {
        let relativePath = project.usesConfiguredGlobalSource == true ? globalRelativePath : projectRelativePath
        precondition(!relativePath.isEmpty, "This rules target is project-only")
        return project.rootURL.appendingPathComponent(relativePath)
    }

    static let all: [RuleSyncTarget] = [
        .init(id: "codex", name: "Codex / 通用 Agent", projectRelativePath: "AGENTS.md", globalRelativePath: ".codex/AGENTS.md"),
        .init(id: "claude", name: "Claude Code", projectRelativePath: "CLAUDE.md", globalRelativePath: ".claude/CLAUDE.md"),
        .init(id: "gemini", name: "Gemini CLI", projectRelativePath: "GEMINI.md", globalRelativePath: ".gemini/GEMINI.md"),
        .init(id: "claude-rules", name: "Claude 规则目录", projectRelativePath: ".claude/rules/skilldeck.md", globalRelativePath: ".claude/rules/skilldeck.md"),
        .init(id: "copilot", name: "GitHub Copilot", projectRelativePath: ".github/copilot-instructions.md", globalRelativePath: ""),
        .init(id: "kiro", name: "Kiro Steering", projectRelativePath: ".kiro/steering/skilldeck.md", globalRelativePath: ".kiro/steering/skilldeck.md"),
        .init(id: "cursor", name: "Cursor 项目规则", projectRelativePath: ".cursor/rules/skilldeck.mdc", globalRelativePath: "", format: .cursorRule)
    ]
}

enum RuleLinkState: String {
    case linked, missing, broken, foreignLink, occupied

    var label: String {
        switch self {
        case .linked: "已同步"
        case .missing: "未同步"
        case .broken: "失效软链"
        case .foreignLink: "指向其他位置"
        case .occupied: "已有规则文件"
        }
    }
}

struct RuleInspection: Identifiable {
    let project: ManagedProject
    let target: RuleSyncTarget
    let sourceURL: URL
    let targetURL: URL
    let state: RuleLinkState

    var id: String { project.id + "|" + target.id }
}

enum RuleChangeKind: String {
    case createLink, replaceItem, removeLink

    var label: String {
        switch self {
        case .createLink: "创建规则软链"
        case .replaceItem: "备份后替换规则"
        case .removeLink: "移除规则软链"
        }
    }
}

struct RuleChange: Identifiable {
    let id = UUID()
    let kind: RuleChangeKind
    let target: RuleSyncTarget
    let sourceURL: URL
    let targetURL: URL
    let summary: String
    let needsResolution: Bool
    var resolution: ProjectConflictResolution = .skip
}

/// RuleSyncFileSystem is kept separate from ProjectSyncFileSystem because rules are individual
/// files, while skills are one complete directory link. This keeps their backup and removal rules
/// unambiguous and makes both workflows directly testable without SwiftUI.
struct RuleSyncFileSystem {
    let fileManager: FileManager
    let backupRoot: URL
    let targets: [RuleSyncTarget]

    init(fileManager: FileManager = .default, backupRoot: URL? = nil, targets: [RuleSyncTarget] = RuleSyncTarget.all) {
        self.fileManager = fileManager
        self.backupRoot = backupRoot ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SkillDeck/RuleSyncBackups", isDirectory: true)
        self.targets = targets
    }

    func sourceURL(for project: ManagedProject) -> URL {
        project.usesConfiguredGlobalSource == true
            ? SkillStorageSettings.globalSkillsURL.deletingLastPathComponent().appendingPathComponent("AGENTS.md")
            : project.rootURL.appendingPathComponent(".agents/AGENTS.md")
    }

    func sourceExists(for project: ManagedProject) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: sourceURL(for: project).path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    func createSource(for project: ManagedProject) throws {
        let source = sourceURL(for: project)
        guard !fileManager.fileExists(atPath: source.path) else { return }
        try fileManager.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Agent Rules\n\n".write(to: source, atomically: true, encoding: .utf8)
    }

    func inspect(project: ManagedProject) -> [RuleInspection] {
        let source = sourceURL(for: project)
        return targets.filter { project.usesConfiguredGlobalSource != true || $0.supportsGlobalSynchronization }.map { target in
            let targetURL = target.url(in: project)
            let state: RuleLinkState
            if target.format == .cursorRule,
               let contents = try? String(contentsOf: targetURL, encoding: .utf8),
               contents == cursorRuleContents() {
                state = .linked
            } else if let destination = linkDestination(at: targetURL) {
                if sameLocation(destination, source) {
                    state = .linked
                } else if fileManager.fileExists(atPath: targetURL.path) {
                    state = .foreignLink
                } else {
                    state = .broken
                }
            } else if fileManager.fileExists(atPath: targetURL.path) {
                state = .occupied
            } else {
                state = .missing
            }
            return RuleInspection(project: project, target: target, sourceURL: source, targetURL: targetURL, state: state)
        }
    }

    func syncPlan(for project: ManagedProject) -> [RuleChange] {
        guard sourceExists(for: project) else { return [] }
        return inspect(project: project).compactMap { inspection in
            guard inspection.state != .linked else { return nil }
            if fileManager.fileExists(atPath: inspection.targetURL.path) || linkDestination(at: inspection.targetURL) != nil {
                return RuleChange(
                    kind: .replaceItem,
                    target: inspection.target,
                    sourceURL: inspection.sourceURL,
                    targetURL: inspection.targetURL,
                    summary: "已有规则文件或外部软链，备份后替换为统一规则。",
                    needsResolution: true
                )
            }
            return RuleChange(
                kind: .createLink,
                target: inspection.target,
                sourceURL: inspection.sourceURL,
                targetURL: inspection.targetURL,
                summary: inspection.target.format == .cursorRule
                    ? "创建 Cursor 规则文件，并引用统一的 AGENTS.md。"
                    : "创建规则软链，指向统一的 AGENTS.md。",
                needsResolution: false
            )
        }
    }

    func removePlan(for project: ManagedProject) -> [RuleChange] {
        inspect(project: project).compactMap { inspection in
            guard inspection.state == .linked else { return nil }
            return RuleChange(
                kind: .removeLink,
                target: inspection.target,
                sourceURL: inspection.sourceURL,
                targetURL: inspection.targetURL,
                summary: "只移除由 SkillDeck 创建的规则软链，不删除统一规则源。",
                needsResolution: false
            )
        }
    }

    func apply(_ change: RuleChange) throws -> String {
        switch change.kind {
        case .createLink:
            try fileManager.createDirectory(at: change.targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writeTarget(for: change)
        case .replaceItem:
            guard change.resolution == .backupAndReplace else { return "保留 \(change.target.name) 的现有规则" }
            let backup = try backup(change.targetURL)
            try fileManager.createDirectory(at: change.targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writeTarget(for: change)
            return "\(change.target.name) 已备份到 \(backup.path)"
        case .removeLink:
            try fileManager.removeItem(at: change.targetURL)
        }
        return "已执行 \(change.kind.label)：\(change.target.name)"
    }

    private func linkDestination(at url: URL) -> URL? {
        guard let value = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else { return nil }
        return URL(fileURLWithPath: value, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
    }

    private func sameLocation(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.resolvingSymlinksInPath().standardizedFileURL.path == rhs.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Cursor displays only `.mdc` project rules in Customize. The wrapper stays tiny and uses
    /// Cursor's documented @file reference syntax, so the editable rule text remains in one source.
    private func cursorRuleContents() -> String {
        "---\ndescription: Shared SkillDeck agent rules\nalwaysApply: true\n---\n@../../.agents/AGENTS.md\n"
    }

    private func writeTarget(for change: RuleChange) throws {
        if change.target.format == .cursorRule {
            try cursorRuleContents().write(to: change.targetURL, atomically: true, encoding: .utf8)
        } else {
            try fileManager.createSymbolicLink(at: change.targetURL, withDestinationURL: change.sourceURL)
        }
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
