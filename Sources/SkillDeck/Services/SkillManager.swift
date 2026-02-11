import Foundation
import Combine

/// SkillManager 是 skill 管理的核心协调器（Orchestrator 模式）
///
/// 它组合了所有子服务（Scanner、Parser、LockFileManager、SymlinkManager、FileSystemWatcher），
/// 对外提供统一的 CRUD 接口。
///
/// @Observable 是 macOS 14+ 引入的宏（Macro），用于替代旧的 ObservableObject 协议。
/// 当标记 @Observable 的 class 的属性变化时，SwiftUI 会自动刷新相关的 View。
/// 类似 Android Jetpack 的 LiveData 或 Vue.js 的响应式数据。
///
/// @MainActor 标记表示这个类的所有方法都在主线程上执行，
/// 因为它持有 UI 状态（skills、agents 数组），而 UI 更新必须在主线程。
/// 类似 Android 的 @UiThread 注解。
@MainActor
@Observable
final class SkillManager {

    // MARK: - Published State（UI 绑定的状态）

    /// 所有发现的 skill（去重后）
    var skills: [Skill] = []

    /// 所有检测到的 Agent
    var agents: [Agent] = []

    /// 是否正在加载
    var isLoading = false

    /// 最近的错误信息
    var errorMessage: String?

    // MARK: - Dependencies（依赖的子服务）

    private let scanner = SkillScanner()
    private let detector = AgentDetector()
    private let lockFileManager = LockFileManager()
    private let watcher = FileSystemWatcher()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupFileWatcher()
    }

    /// 设置文件系统监控
    /// 当文件系统变化时，自动触发刷新
    private func setupFileWatcher() {
        // sink 是 Combine 框架的订阅方法（类似 RxJava 的 subscribe）
        // 当 watcher.onChange 发送事件时，执行闭包中的代码
        watcher.onChange
            .sink { [weak self] in
                // Task { } 创建一个异步任务（类似 Go 的 go func(){}）
                Task { await self?.refresh() }
            }
            .store(in: &cancellables)  // 保存订阅关系，防止被提前释放
    }

    // MARK: - Core Operations

    /// 刷新所有数据：重新检测 Agent 和扫描 skill
    func refresh() async {
        isLoading = true
        errorMessage = nil

        do {
            // 并发执行 Agent 检测和 Skill 扫描
            // async let 类似 Go 的 goroutine + channel，两个任务并行执行
            async let detectedAgents = detector.detectAll()
            async let scannedSkills = scanner.scanAll()

            agents = await detectedAgents
            var allSkills = try await scannedSkills

            // 填充 lock file 信息
            if await lockFileManager.exists {
                if let lockFile = try? await lockFileManager.read() {
                    for i in allSkills.indices {
                        allSkills[i].lockEntry = lockFile.skills[allSkills[i].id]
                    }
                }
            }

            skills = allSkills

            // 启动文件系统监控
            startWatching()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// 启动文件系统监控，监控所有相关目录
    private func startWatching() {
        var paths: [URL] = [SkillScanner.sharedSkillsURL]
        for agent in AgentType.allCases where agent != .codex {
            paths.append(agent.skillsDirectoryURL)
        }
        watcher.startWatching(paths: paths)
    }

    // MARK: - F04: Skill Deletion

    /// 删除一个 skill
    ///
    /// 删除流程：
    /// 1. 移除所有 Agent 中的直接安装 symlink（跳过继承安装）
    /// 2. 删除 canonical 目录（真实文件）
    /// 3. 更新 lock file
    /// 4. 刷新数据
    ///
    /// 继承安装的 symlink 不需要单独删除：它们指向源 Agent 目录中的 symlink，
    /// 而源 Agent 的 symlink 会在第 1 步被删除；即使不删，canonical 目录删除后
    /// 它们也会变成 dangling symlink（悬空链接），不影响功能
    func deleteSkill(_ skill: Skill) async throws {
        // 1. 移除所有直接安装的 symlink（跳过继承安装）
        for installation in skill.installations where installation.isSymlink && !installation.isInherited {
            try SymlinkManager.removeSymlink(
                skillName: skill.id,
                from: installation.agentType
            )
        }

        // 2. 删除 canonical 目录
        let fm = FileManager.default
        if fm.fileExists(atPath: skill.canonicalURL.path) {
            try fm.removeItem(at: skill.canonicalURL)
        }

        // 3. 更新 lock file（如果有记录的话）
        if skill.lockEntry != nil {
            try await lockFileManager.removeEntry(skillName: skill.id)
        }

        // 4. 刷新列表
        await refresh()
    }

    // MARK: - F05: Save Edited Skill

    /// 保存编辑后的 skill（更新 SKILL.md）
    func saveSkill(_ skill: Skill, metadata: SkillMetadata, markdownBody: String) async throws {
        let content = try SkillMDParser.serialize(metadata: metadata, markdownBody: markdownBody)
        let skillMDURL = skill.canonicalURL.appendingPathComponent("SKILL.md")
        try content.write(to: skillMDURL, atomically: true, encoding: .utf8)
        await refresh()
    }

    // MARK: - F06: Agent Assignment（Toggle Symlink）

    /// 将 skill 安装到指定 Agent（创建 symlink）
    func assignSkill(_ skill: Skill, to agent: AgentType) async throws {
        try SymlinkManager.createSymlink(from: skill.canonicalURL, to: agent)
        await refresh()
    }

    /// 从指定 Agent 卸载 skill（删除 symlink）
    func unassignSkill(_ skill: Skill, from agent: AgentType) async throws {
        try SymlinkManager.removeSymlink(skillName: skill.id, from: agent)
        await refresh()
    }

    /// 切换 skill 在指定 Agent 上的安装状态
    ///
    /// 防护逻辑：如果是继承安装（isInherited），直接返回不做任何操作
    /// 这是 Service 层的防御，即使 UI 层禁用了 Toggle，也确保不会误操作继承安装
    func toggleAssignment(_ skill: Skill, agent: AgentType) async throws {
        let installation = skill.installations.first { $0.agentType == agent }

        // 防护：继承安装不可 toggle（继承安装由源 Agent 管理）
        if let installation, installation.isInherited {
            return
        }

        // 防护：Codex canonical 安装不可 toggle
        // Codex 的 skills 目录与 canonical 共享目录相同（~/.agents/skills/），
        // 其安装记录的 isSymlink 为 false，表示是原始文件而非 symlink。
        // 删除 canonical 文件应使用 deleteSkill，不应通过 toggle 操作
        if agent == .codex, let installation, !installation.isSymlink {
            return
        }

        let isInstalled = installation != nil
        if isInstalled {
            try await unassignSkill(skill, from: agent)
        } else {
            try await assignSkill(skill, to: agent)
        }
    }

    // MARK: - Helper Methods

    /// 按 Agent 过滤 skill
    func skills(for agentType: AgentType) -> [Skill] {
        skills.filter { skill in
            skill.installations.contains { $0.agentType == agentType }
        }
    }

    /// 搜索 skill（按名称和描述）
    func search(query: String) -> [Skill] {
        guard !query.isEmpty else { return skills }
        let lowered = query.lowercased()
        return skills.filter {
            $0.displayName.lowercased().contains(lowered) ||
            $0.metadata.description.lowercased().contains(lowered)
        }
    }
}
