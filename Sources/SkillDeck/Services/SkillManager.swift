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

    // MARK: - Error Types

    /// 手动关联仓库时的错误类型
    /// LocalizedError 协议提供人类可读的错误描述（类似 Java 的 getMessage()）
    enum LinkError: Error, LocalizedError {
        /// 仓库中未找到与当前 skill 匹配的目录
        case skillNotFoundInRepo(String)
        /// git 操作失败
        case gitError(String)

        var errorDescription: String? {
            switch self {
            case .skillNotFoundInRepo(let name):
                "Skill '\(name)' not found in repository"
            case .gitError(let message):
                message
            }
        }
    }

    // MARK: - Published State（UI 绑定的状态）

    /// 所有发现的 skill（去重后）
    var skills: [Skill] = []

    /// 所有检测到的 Agent
    var agents: [Agent] = []

    /// 是否正在加载
    var isLoading = false

    /// 最近的错误信息
    var errorMessage: String?

    /// F12: 是否正在批量检查更新（显示全局进度）
    var isCheckingUpdates = false

    /// F12: 更新状态（按 skill id 索引，跨 refresh 保持）
    /// 存储每个 skill 的更新检查状态（5 种状态），键为 skill.id
    /// 类型从 [String: Bool] 改为 [String: SkillUpdateStatus]，支持更丰富的 UI 反馈
    var updateStatuses: [String: SkillUpdateStatus] = [:]

    // MARK: - Dependencies（依赖的子服务）

    private let scanner = SkillScanner()
    private let detector = AgentDetector()
    private let lockFileManager = LockFileManager()
    private let watcher = FileSystemWatcher()
    /// F10/F12: Git 操作服务，用于安装和更新检查
    private let gitService = GitService()
    /// F12: SkillDeck 私有的 commit hash 缓存，独立于 .skill-lock.json
    /// 存储在 ~/.agents/.skilldeck-cache.json，不污染 npx skills 的 lock file 格式
    private let commitHashCache = CommitHashCache()
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

            // 为没有 lockEntry 但有手动关联信息的 skill 合成 LockEntry
            // 这样这些 skill 可以复用现有的更新检查流程（checkForUpdate、checkAllUpdates）
            let linkedInfos = await commitHashCache.getAllLinkedInfos()
            for i in allSkills.indices {
                if allSkills[i].lockEntry == nil, let linked = linkedInfos[allSkills[i].id] {
                    // 合成 LockEntry：字段与 LinkedSkillInfo 对齐
                    // installedAt/updatedAt 使用关联时间（仅供 UI 显示）
                    allSkills[i].lockEntry = LockEntry(
                        source: linked.source,
                        sourceType: linked.sourceType,
                        sourceUrl: linked.sourceUrl,
                        skillPath: linked.skillPath,
                        skillFolderHash: linked.skillFolderHash,
                        installedAt: linked.linkedAt,
                        updatedAt: linked.linkedAt
                    )
                }
            }

            skills = allSkills

            // F12: 恢复之前的更新状态（refresh 不应清除更新检查结果）
            // 同时从 CommitHashCache 加载本地 commit hash
            // 从 SkillUpdateStatus 枚举恢复 hasUpdate 布尔值：只有 .hasUpdate 状态才算有更新
            for i in skills.indices {
                if let status = updateStatuses[skills[i].id] {
                    skills[i].hasUpdate = (status == .hasUpdate)
                }
                // 从 CommitHashCache 读取本地 commit hash
                // 用于 UI 中显示 hash 对比和生成 GitHub compare URL
                skills[i].localCommitHash = await commitHashCache.getHash(for: skills[i].id)
            }

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

    // MARK: - F10: One-Click Install

    /// 从克隆的仓库安装 skill 到本地
    ///
    /// 安装流程：
    /// 1. 获取 tree hash（用于 lock file 记录，后续检测更新）
    /// 2. 拷贝文件到 canonical 目录（~/.agents/skills/<name>/）
    /// 3. 为选中的 Agent 创建 symlink（跳过 Codex，因为它共享 canonical 目录）
    /// 4. 创建/更新 lock file 条目
    /// 5. 刷新 UI
    ///
    /// - Parameters:
    ///   - repoDir: 克隆仓库的本地临时目录
    ///   - skill: 要安装的 skill 信息（从 GitService.scanSkillsInRepo 获取）
    ///   - repoSource: 仓库来源标识（如 "vercel-labs/skills"，用于 lock file）
    ///   - repoURL: 完整的仓库 URL（如 "https://github.com/vercel-labs/skills.git"）
    ///   - targetAgents: 要安装到的 Agent 集合
    func installSkill(
        from repoDir: URL,
        skill: GitService.DiscoveredSkill,
        repoSource: String,
        repoURL: String,
        targetAgents: Set<AgentType>
    ) async throws {
        let fm = FileManager.default

        // 1. 获取 tree hash（git rev-parse HEAD:<folderPath>）
        let treeHash = try await gitService.getTreeHash(for: skill.folderPath, in: repoDir)

        // 1.5 获取 commit hash 并写入 CommitHashCache（独立于 lock file）
        // commit hash 用于后续生成 GitHub compare URL，显示更新差异
        let commitHash = try await gitService.getCommitHash(in: repoDir)
        await commitHashCache.setHash(for: skill.id, hash: commitHash)
        try await commitHashCache.save()

        // 2. 拷贝到 canonical 目录
        // canonical 路径：~/.agents/skills/<skillName>/
        let canonicalDir = SkillScanner.sharedSkillsURL.appendingPathComponent(skill.id)
        let sourceDir = repoDir.appendingPathComponent(skill.folderPath)

        // 如果已存在，先删除再拷贝（覆盖安装）
        if fm.fileExists(atPath: canonicalDir.path) {
            try fm.removeItem(at: canonicalDir)
        }

        // 确保父目录存在
        if !fm.fileExists(atPath: SkillScanner.sharedSkillsURL.path) {
            try fm.createDirectory(at: SkillScanner.sharedSkillsURL, withIntermediateDirectories: true)
        }

        // copyItem 类似 cp -r，递归拷贝整个目录
        try fm.copyItem(at: sourceDir, to: canonicalDir)

        // 3. 为选中的 Agent 创建 symlink
        for agent in targetAgents {
            // Codex 直接使用 ~/.agents/skills/ 目录，不需要 symlink
            if agent == .codex { continue }
            // 使用 try? 忽略已存在的 symlink 错误（幂等操作）
            try? SymlinkManager.createSymlink(from: canonicalDir, to: agent)
        }

        // 4. 更新 lock file
        // 确保 lock file 存在（首次安装时可能不存在）
        try await lockFileManager.createIfNotExists()

        // ISO 8601 时间戳（与 npx skills CLI 格式一致）
        let now = ISO8601DateFormatter().string(from: Date())
        let entry = LockEntry(
            source: repoSource,
            sourceType: "github",
            sourceUrl: repoURL,
            skillPath: skill.skillMDPath,
            skillFolderHash: treeHash,
            installedAt: now,
            updatedAt: now
        )
        try await lockFileManager.updateEntry(skillName: skill.id, entry: entry)

        // 5. 刷新 UI
        await refresh()
    }

    // MARK: - F12: Update Check

    /// 检查单个 skill 的更新
    ///
    /// 流程：
    /// 1. 从 lockEntry 获取源仓库 URL 和 skillPath
    /// 2. 检查 CommitHashCache 是否有本地 commit hash
    ///    - 有：使用 shallow 克隆（快速，只需获取远程最新状态）
    ///    - 没有（老 skill，通过 npx skills 安装）：使用完整克隆，通过 git 历史搜索 backfill
    /// 3. 获取远程 tree hash 和 commit hash
    /// 4. 与本地 lockEntry.skillFolderHash 比对
    /// 5. 清理临时目录
    ///
    /// - Parameter skill: 要检查的 skill（必须有 lockEntry）
    /// - Returns: 元组 (是否有更新, 远程 tree hash, 远程 commit hash)
    func checkForUpdate(skill: Skill) async throws -> (hasUpdate: Bool, remoteHash: String?, remoteCommitHash: String?) {
        guard let lockEntry = skill.lockEntry else {
            return (false, nil, nil)
        }

        // 从 skillPath 推导 folderPath（去掉末尾的 "/SKILL.md"）
        let folderPath: String
        if lockEntry.skillPath.hasSuffix("/SKILL.md") {
            folderPath = String(lockEntry.skillPath.dropLast("/SKILL.md".count))
        } else {
            folderPath = lockEntry.skillPath
        }

        // 检查 CommitHashCache 是否有本地 commit hash
        let localCommitHash = await commitHashCache.getHash(for: skill.id)
        // 如果没有 commit hash（老 skill），需要完整克隆以搜索 git 历史进行 backfill
        let needsBackfill = localCommitHash == nil

        // 根据是否需要 backfill 决定克隆深度
        let repoDir = try await gitService.cloneRepo(repoURL: lockEntry.sourceUrl, shallow: !needsBackfill)
        defer {
            // defer 确保无论函数如何返回都会执行清理（类似 Go 的 defer 或 Java 的 finally）
            Task { await gitService.cleanupTempDirectory(repoDir) }
        }

        // 获取远程 tree hash
        let remoteHash = try await gitService.getTreeHash(for: folderPath, in: repoDir)

        // 获取远程 commit hash
        let remoteCommitHash = try await gitService.getCommitHash(in: repoDir)

        // Backfill：如果本地没有 commit hash，从 git 历史中搜索匹配的 commit
        if needsBackfill {
            if let foundHash = try await gitService.findCommitForTreeHash(
                treeHash: lockEntry.skillFolderHash, folderPath: folderPath, in: repoDir
            ) {
                // 找到匹配的 commit hash，持久化到缓存（下次不再搜索）
                await commitHashCache.setHash(for: skill.id, hash: foundHash)
                try? await commitHashCache.save()
            }
        }

        // 比对 hash
        let hasUpdate = remoteHash != lockEntry.skillFolderHash
        return (hasUpdate, remoteHash, remoteCommitHash)
    }

    /// 批量检查所有有 lockEntry 的 skill 的更新
    ///
    /// 优化策略：按 sourceUrl 分组，同一仓库只克隆一次，
    /// 然后批量获取每个 skill 的 tree hash 和 commit hash 进行比对。
    ///
    /// 智能克隆深度：检查该组中是否有任何 skill 缺少 commit hash（从 cache 查），
    /// 如果有则使用完整克隆（需要搜索 git 历史进行 backfill），否则使用 shallow 克隆（更快）。
    func checkAllUpdates() async {
        isCheckingUpdates = true
        defer { isCheckingUpdates = false }

        // 收集所有有 lockEntry 的 skill，按 sourceUrl 分组
        // Dictionary(grouping:by:) 类似 Java Stream 的 Collectors.groupingBy()
        let skillsWithLock = skills.filter { $0.lockEntry != nil }

        // 预设所有待检查的 skill 为 .checking 状态
        // 这样 UI 列表中会立即显示 spinner，用户知道哪些 skill 正在被检查
        for skill in skillsWithLock {
            updateStatuses[skill.id] = .checking
        }

        let grouped = Dictionary(grouping: skillsWithLock) { $0.lockEntry!.sourceUrl }

        for (sourceUrl, groupSkills) in grouped {
            do {
                // 检查该组中是否有任何 skill 缺少 commit hash
                // 如果有，需要完整克隆以支持 backfill（搜索 git 历史还原 commit hash）
                var needsFullClone = false
                for skill in groupSkills {
                    let cached = await commitHashCache.getHash(for: skill.id)
                    if cached == nil {
                        needsFullClone = true
                        break
                    }
                }

                // 每个仓库只克隆一次，根据是否需要 backfill 决定克隆深度
                let repoDir = try await gitService.cloneRepo(repoURL: sourceUrl, shallow: !needsFullClone)

                // 获取远程最新 commit hash（整个仓库共享一个 HEAD commit）
                let remoteCommitHash = try await gitService.getCommitHash(in: repoDir)

                for skill in groupSkills {
                    guard let lockEntry = skill.lockEntry else { continue }

                    // 推导 folderPath
                    let folderPath: String
                    if lockEntry.skillPath.hasSuffix("/SKILL.md") {
                        folderPath = String(lockEntry.skillPath.dropLast("/SKILL.md".count))
                    } else {
                        folderPath = lockEntry.skillPath
                    }

                    do {
                        let remoteHash = try await gitService.getTreeHash(for: folderPath, in: repoDir)
                        let hasUpdate = remoteHash != lockEntry.skillFolderHash

                        // 更新状态字典：使用枚举值替代布尔值
                        updateStatuses[skill.id] = hasUpdate ? .hasUpdate : .upToDate

                        // Backfill：对缺少 commit hash 的 skill 从 git 历史中搜索
                        let localCached = await commitHashCache.getHash(for: skill.id)
                        var currentLocalHash = localCached
                        if localCached == nil {
                            if let foundHash = try? await gitService.findCommitForTreeHash(
                                treeHash: lockEntry.skillFolderHash, folderPath: folderPath, in: repoDir
                            ) {
                                await commitHashCache.setHash(for: skill.id, hash: foundHash)
                                currentLocalHash = foundHash
                            }
                        }

                        // 同步到 skills 数组（找到对应的 skill 并更新）
                        if let index = skills.firstIndex(where: { $0.id == skill.id }) {
                            skills[index].hasUpdate = hasUpdate
                            skills[index].remoteTreeHash = hasUpdate ? remoteHash : nil
                            // 存储远程 commit hash，用于生成 GitHub compare URL
                            skills[index].remoteCommitHash = hasUpdate ? remoteCommitHash : nil
                            // 更新本地 commit hash（可能刚通过 backfill 获取）
                            skills[index].localCommitHash = currentLocalHash
                        }
                    } catch {
                        // 单个 skill 检查失败：标记为 .error 状态，UI 会显示警告图标
                        updateStatuses[skill.id] = .error(error.localizedDescription)
                        continue
                    }
                }

                // Backfill 后统一保存一次缓存（减少磁盘 IO）
                try? await commitHashCache.save()

                // 清理临时目录
                await gitService.cleanupTempDirectory(repoDir)
            } catch {
                // 仓库克隆失败：该仓库下所有 skill 都标记为 .error
                for skill in groupSkills {
                    updateStatuses[skill.id] = .error(error.localizedDescription)
                }
                continue
            }
        }
    }

    /// 执行更新：用远程文件覆盖本地，更新 lock entry
    ///
    /// - Parameters:
    ///   - skill: 要更新的 skill
    ///   - remoteHash: 远程最新的 tree hash
    func updateSkill(_ skill: Skill, remoteHash: String) async throws {
        guard let lockEntry = skill.lockEntry else { return }

        // 推导 folderPath
        let folderPath: String
        if lockEntry.skillPath.hasSuffix("/SKILL.md") {
            folderPath = String(lockEntry.skillPath.dropLast("/SKILL.md".count))
        } else {
            folderPath = lockEntry.skillPath
        }

        // 1. 克隆源仓库
        let repoDir = try await gitService.shallowClone(repoURL: lockEntry.sourceUrl)

        // 2. 获取新的 commit hash 并写入缓存
        let newCommitHash = try await gitService.getCommitHash(in: repoDir)
        await commitHashCache.setHash(for: skill.id, hash: newCommitHash)
        try? await commitHashCache.save()

        // 3. 拷贝文件覆盖 canonical 目录
        let fm = FileManager.default
        let sourceDir = repoDir.appendingPathComponent(folderPath)
        let canonicalDir = skill.canonicalURL

        // 删除旧文件再拷贝新文件
        if fm.fileExists(atPath: canonicalDir.path) {
            try fm.removeItem(at: canonicalDir)
        }
        try fm.copyItem(at: sourceDir, to: canonicalDir)

        // 4. 更新 lock entry（新 hash + 新 updatedAt）
        let now = ISO8601DateFormatter().string(from: Date())
        var updatedEntry = lockEntry
        updatedEntry.skillFolderHash = remoteHash
        updatedEntry.updatedAt = now
        try await lockFileManager.updateEntry(skillName: skill.id, entry: updatedEntry)

        // 5. 清理临时目录
        await gitService.cleanupTempDirectory(repoDir)

        // 6. 清除更新状态（更新完成后恢复为未检查状态）
        updateStatuses[skill.id] = .notChecked

        // 7. 刷新 UI
        await refresh()
    }

    // MARK: - Helper Methods

    /// 获取指定 skill 的本地 commit hash（从 CommitHashCache 读取）
    ///
    /// 这个方法暴露给 ViewModel 使用，因为 commitHashCache 是 private 的。
    /// 在 checkForUpdate 后调用，获取可能通过 backfill 新获取到的 commit hash。
    func getCachedCommitHash(for skillName: String) async -> String? {
        await commitHashCache.getHash(for: skillName)
    }

    /// 按 Agent 过滤 skill
    func skills(for agentType: AgentType) -> [Skill] {
        skills.filter { skill in
            skill.installations.contains { $0.agentType == agentType }
        }
    }

    /// 搜索 skill（按名称、描述和作者/来源）
    /// 除了匹配 displayName 和 description 外，还支持：
    /// - lockEntry?.source：来自 lock file 的仓库来源（如 "crossoverJie/skills"），适合按组织/作者筛选
    /// - metadata.author：来自 SKILL.md frontmatter 的 author 字段（可选）
    func search(query: String) -> [Skill] {
        guard !query.isEmpty else { return skills }
        let lowered = query.lowercased()
        return skills.filter {
            $0.displayName.lowercased().contains(lowered) ||
            $0.metadata.description.lowercased().contains(lowered) ||
            ($0.lockEntry?.source.lowercased().contains(lowered) ?? false) ||
            ($0.metadata.author?.lowercased().contains(lowered) ?? false)
        }
    }

    // MARK: - Link to Repository（手动关联仓库）

    /// 将无 lockEntry 的 skill 手动关联到 GitHub 仓库
    ///
    /// 流程：
    /// 1. normalizeRepoURL() 校验并规范化 URL 输入
    /// 2. shallow clone 远程仓库
    /// 3. scanSkillsInRepo 扫描仓库中的 skill，按 skill.id 匹配
    /// 4. 获取 tree hash + commit hash
    /// 5. 同步远程文件到本地 canonical 目录（保证本地文件与 hash 一致）
    /// 6. 写入 commitHashCache（linkedSkills + skills 两个 map）
    /// 7. refresh() 刷新 UI
    ///
    /// 关联信息存储在 SkillDeck 私有缓存（~/.agents/.skilldeck-cache.json），
    /// 不修改 skill-lock.json（避免影响 npx skills 的行为）。
    /// refresh() 时会从缓存读取关联信息，合成 LockEntry 挂到 Skill 模型上，
    /// 从而复用现有的更新检查流程。
    ///
    /// - Parameters:
    ///   - skill: 要关联的 skill（必须无 lockEntry）
    ///   - repoInput: 用户输入的仓库地址（支持 "owner/repo" 或完整 URL）
    func linkSkillToRepository(_ skill: Skill, repoInput: String) async throws {
        // 1. 校验并规范化 URL
        let (repoURL, source) = try GitService.normalizeRepoURL(repoInput)

        // 2. shallow clone 远程仓库
        let repoDir: URL
        do {
            repoDir = try await gitService.shallowClone(repoURL: repoURL)
        } catch {
            throw LinkError.gitError(error.localizedDescription)
        }
        // defer 确保无论函数如何返回都会执行清理（类似 Go 的 defer）
        defer {
            Task { await gitService.cleanupTempDirectory(repoDir) }
        }

        // 3. 扫描仓库中的 skill，按 skill.id 匹配
        let discoveredSkills = await gitService.scanSkillsInRepo(repoDir: repoDir)
        guard let matched = discoveredSkills.first(where: { $0.id == skill.id }) else {
            throw LinkError.skillNotFoundInRepo(skill.id)
        }

        // 4. 获取 tree hash 和 commit hash
        let treeHash = try await gitService.getTreeHash(for: matched.folderPath, in: repoDir)
        let commitHash = try await gitService.getCommitHash(in: repoDir)

        // 5. 同步远程文件到本地 canonical 目录
        // 确保本地文件与存储的 skillFolderHash 一致，
        // 否则后续 checkForUpdate 的 hash 对比基线会不准确
        let fm = FileManager.default
        let sourceDir = repoDir.appendingPathComponent(matched.folderPath)
        let canonicalDir = skill.canonicalURL

        // 删除旧文件再拷贝新文件（与 installSkill/updateSkill 一致）
        if fm.fileExists(atPath: canonicalDir.path) {
            try fm.removeItem(at: canonicalDir)
        }
        // 确保父目录存在
        let parentDir = canonicalDir.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        // copyItem 递归拷贝整个目录（类似 cp -r）
        try fm.copyItem(at: sourceDir, to: canonicalDir)

        // 6. 写入 commitHashCache（两个 map）
        // 6a. skills map：存储 commit hash（用于后续 compare URL）
        await commitHashCache.setHash(for: skill.id, hash: commitHash)

        // 6b. linkedSkills map：存储完整的关联信息（用于 refresh 时合成 LockEntry）
        let now = ISO8601DateFormatter().string(from: Date())
        let linkedInfo = CommitHashCache.LinkedSkillInfo(
            source: source,
            sourceType: "github",
            sourceUrl: repoURL,
            skillPath: matched.skillMDPath,
            skillFolderHash: treeHash,
            linkedAt: now
        )
        await commitHashCache.setLinkedInfo(for: skill.id, info: linkedInfo)

        // 持久化到磁盘
        try await commitHashCache.save()

        // 7. 刷新 UI —— refresh 会从缓存读取关联信息，合成 LockEntry
        await refresh()
    }
}
