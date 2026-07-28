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
    private let defaultName: String

    /// Target display names are computed so they refresh with the app language instead of
    /// being frozen when the static target registry is first initialized.
    var name: String {
        switch id {
        case "codex": L10n.currentString(L10nKeys.ruleTargetCodex)
        case "claude-rules": L10n.currentString(L10nKeys.ruleTargetClaudeDirectory)
        case "cursor": L10n.currentString(L10nKeys.ruleTargetCursor)
        default: defaultName
        }
    }
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
        self.defaultName = name
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
        .init(id: "codex", name: "Codex / Generic Agent", projectRelativePath: "AGENTS.md", globalRelativePath: ".codex/AGENTS.md"),
        .init(id: "claude", name: "Claude Code", projectRelativePath: "CLAUDE.md", globalRelativePath: ".claude/CLAUDE.md"),
        .init(id: "gemini", name: "Gemini CLI", projectRelativePath: "GEMINI.md", globalRelativePath: ".gemini/GEMINI.md"),
        .init(id: "claude-rules", name: "Claude Rules Directory", projectRelativePath: ".claude/rules/skilldeck.md", globalRelativePath: ".claude/rules/skilldeck.md"),
        .init(id: "copilot", name: "GitHub Copilot", projectRelativePath: ".github/copilot-instructions.md", globalRelativePath: ""),
        .init(id: "kiro", name: "Kiro Steering", projectRelativePath: ".kiro/steering/skilldeck.md", globalRelativePath: ".kiro/steering/skilldeck.md"),
        .init(id: "cursor", name: "Cursor Project Rules", projectRelativePath: ".cursor/rules/skilldeck.mdc", globalRelativePath: "", format: .cursorRule)
    ]
}

enum RuleLinkState: String {
    case linked, missing, broken, foreignLink, occupied

    var label: String {
        switch self {
        case .linked: L10n.currentString(L10nKeys.syncStateLinked)
        case .missing: L10n.currentString(L10nKeys.syncStateMissing)
        case .broken: L10n.currentString(L10nKeys.syncStateBroken)
        case .foreignLink: L10n.currentString(L10nKeys.syncStateForeignLink)
        case .occupied: L10n.currentString(L10nKeys.syncStateOccupied)
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
        case .createLink: L10n.currentString(L10nKeys.ruleChangeCreate)
        case .replaceItem: L10n.currentString(L10nKeys.ruleChangeReplace)
        case .removeLink: L10n.currentString(L10nKeys.ruleChangeRemove)
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
                    summary: L10n.currentString(L10nKeys.ruleSummaryReplace),
                    needsResolution: true
                )
            }
            return RuleChange(
                kind: .createLink,
                target: inspection.target,
                sourceURL: inspection.sourceURL,
                targetURL: inspection.targetURL,
                summary: inspection.target.format == .cursorRule
                    ? L10n.currentString(L10nKeys.ruleSummaryCursorCreate)
                    : L10n.currentString(L10nKeys.ruleSummaryCreate),
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
                summary: L10n.currentString(L10nKeys.ruleSummaryRemove),
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
            guard change.resolution == .backupAndReplace else { return L10n.currentFormat(L10nKeys.ruleResultKeep, change.target.name) }
            let backup = try backup(change.targetURL)
            try fileManager.createDirectory(at: change.targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writeTarget(for: change)
            return L10n.currentFormat(L10nKeys.ruleResultBackup, change.target.name, backup.path)
        case .removeLink:
            try fileManager.removeItem(at: change.targetURL)
        }
        return L10n.currentFormat(L10nKeys.ruleResultApplied, change.kind.label, change.target.name)
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
