import Foundation

/// CommitHashCache 是 SkillDeck 私有的 commit hash 缓存服务
///
/// **设计决策**：不修改 `.skill-lock.json` 格式，避免污染 `npx skills` 共用的文件。
/// SkillDeck 将 commit hash 独立存储在 `~/.agents/.skilldeck-cache.json` 中，
/// 这样 `npx skills add/remove` 操作不会受到任何影响。
///
/// 文件格式：
/// ```json
/// {
///   "skills": {
///     "skill-name": "abc123def456...",
///     "another-skill": "789xyz..."
///   }
/// }
/// ```
///
/// 使用 `actor` 保证线程安全，因为多个操作可能同时读写缓存文件。
/// actor 类似 Go 的 goroutine + mutex，编译器自动保证同一时间只有一个方法在执行。
actor CommitHashCache {

    // MARK: - Data Types

    /// 缓存文件的 JSON 结构
    /// Codable 协议让 Swift 自动生成 JSON 编解码代码（类似 Go 的 json struct tag）
    private struct CacheFile: Codable {
        /// 存储 skill name → commit hash 的映射
        var skills: [String: String]
        /// 存储手动关联的 skill → 仓库信息的映射
        /// optional 保证向后兼容：旧格式文件中没有此字段，解码时自动为 nil
        var linkedSkills: [String: LinkedSkillInfo]?
        /// 存储用户 scan 过的仓库历史记录
        /// optional 保证向后兼容：旧格式文件中没有此字段，解码时自动为 nil
        var repoHistory: [RepoHistoryEntry]?
    }

    /// Scan 过的 repo 历史记录
    ///
    /// 记录用户在 Install Sheet 中成功 scan 过的 GitHub 仓库，
    /// 下次打开 Install Sheet 时可以快速选择历史仓库，无需重新输入 URL。
    /// Codable 协议自动生成 JSON 序列化/反序列化代码
    struct RepoHistoryEntry: Codable, Equatable {
        /// 仓库来源标识（如 "crossoverJie/skills"）
        var source: String
        /// 完整仓库 URL（如 "https://github.com/crossoverJie/skills.git"）
        var sourceUrl: String
        /// 最近 scan 的时间（ISO 8601 格式）
        var scannedAt: String
    }

    /// 手动关联 skill 到 GitHub 仓库的信息
    ///
    /// 当 skill 没有 lockEntry（如直接放在 ~/.claude/skills/ 中的 skill）时，
    /// 用户可以手动将其关联到 GitHub 仓库，信息存储在此结构中。
    /// 字段与 LockEntry 对齐，方便在 refresh 时合成 LockEntry。
    /// Codable 协议自动生成 JSON 序列化/反序列化代码
    struct LinkedSkillInfo: Codable {
        /// 仓库来源标识（如 "crossoverJie/skills"）
        var source: String
        /// 来源类型（目前固定 "github"）
        var sourceType: String
        /// 完整仓库 URL（如 "https://github.com/crossoverJie/skills.git"）
        var sourceUrl: String
        /// SKILL.md 在仓库中的相对路径（如 "skills/auto-blog-cover/SKILL.md"）
        var skillPath: String
        /// skill 文件夹的 git tree hash（用于检测更新）
        var skillFolderHash: String
        /// 关联时间（ISO 8601 格式）
        var linkedAt: String
    }

    // MARK: - Properties

    /// 缓存文件的默认路径：~/.agents/.skilldeck-cache.json
    /// `static let` 是编译时常量，类似 Java 的 static final
    static let defaultPath: URL = {
        let home = NSString(string: "~/.agents/.skilldeck-cache.json").expandingTildeInPath
        return URL(fileURLWithPath: home)
    }()

    /// 当前使用的缓存文件路径（可在测试中覆盖）
    private let filePath: URL

    /// 内存缓存：skill name → commit hash
    /// 首次访问时从磁盘加载，后续操作直接读写内存，save() 时写回磁盘
    private var cache: [String: String] = [:]

    /// 内存缓存：skill name → 手动关联的仓库信息
    /// 用于存储没有 lockEntry 的 skill 手动关联的 GitHub 仓库信息
    private var linkedSkillsCache: [String: LinkedSkillInfo] = [:]

    /// 内存缓存：用户 scan 过的仓库历史记录
    /// 按 source 去重，最新 scan 的排在最前面，最多保留 20 条
    private var repoHistoryCache: [RepoHistoryEntry] = []

    /// 是否已从磁盘加载过（避免重复读取）
    private var isLoaded = false

    // MARK: - Initialization

    init(filePath: URL = CommitHashCache.defaultPath) {
        self.filePath = filePath
    }

    // MARK: - Public Methods

    /// 获取指定 skill 的 commit hash
    ///
    /// - Parameter skillName: skill 的唯一标识（目录名）
    /// - Returns: commit hash，如果未缓存则返回 nil
    func getHash(for skillName: String) -> String? {
        ensureLoaded()
        return cache[skillName]
    }

    /// 设置指定 skill 的 commit hash（仅写入内存，需调用 save() 持久化）
    ///
    /// - Parameters:
    ///   - skillName: skill 的唯一标识（目录名）
    ///   - hash: 完整的 commit hash（40 字符 SHA-1）
    func setHash(for skillName: String, hash: String) {
        ensureLoaded()
        cache[skillName] = hash
    }

    // MARK: - Linked Skills Methods（手动关联仓库信息）

    /// 获取指定 skill 的手动关联信息
    ///
    /// - Parameter skillName: skill 的唯一标识（目录名）
    /// - Returns: LinkedSkillInfo，如果未关联则返回 nil
    func getLinkedInfo(for skillName: String) -> LinkedSkillInfo? {
        ensureLoaded()
        return linkedSkillsCache[skillName]
    }

    /// 设置指定 skill 的手动关联信息（仅写入内存，需调用 save() 持久化）
    ///
    /// - Parameters:
    ///   - skillName: skill 的唯一标识（目录名）
    ///   - info: 关联的仓库信息
    func setLinkedInfo(for skillName: String, info: LinkedSkillInfo) {
        ensureLoaded()
        linkedSkillsCache[skillName] = info
    }

    /// 移除指定 skill 的手动关联信息（仅写入内存，需调用 save() 持久化）
    ///
    /// 当用户通过 updateSkill 正式写入 lock file 后，
    /// 可以移除 cache 中的关联信息（已不再需要）
    ///
    /// - Parameter skillName: skill 的唯一标识（目录名）
    func removeLinkedInfo(for skillName: String) {
        ensureLoaded()
        linkedSkillsCache.removeValue(forKey: skillName)
    }

    /// 获取所有手动关联的 skill 信息
    ///
    /// 用于 SkillManager.refresh() 中遍历所有关联信息，
    /// 为没有 lockEntry 的 skill 合成 LockEntry
    func getAllLinkedInfos() -> [String: LinkedSkillInfo] {
        ensureLoaded()
        return linkedSkillsCache
    }

    // MARK: - Repo History Methods（scan 历史记录）

    /// 添加或更新一条 repo scan 历史记录
    ///
    /// 按 source（如 "owner/repo"）去重：如果已存在同名记录，更新时间戳并移到最前面。
    /// 最多保留 20 条历史记录（FIFO，超出时丢弃最旧的）。
    /// 仅写入内存，需调用 save() 持久化到磁盘。
    ///
    /// - Parameters:
    ///   - source: 仓库来源标识（如 "crossoverJie/skills"）
    ///   - sourceUrl: 完整仓库 URL（如 "https://github.com/crossoverJie/skills.git"）
    func addRepoHistory(source: String, sourceUrl: String) {
        ensureLoaded()

        // 移除同 source 的旧记录（忽略大小写去重，GitHub 地址不区分大小写）
        // removeAll(where:) 类似 Java Stream 的 filter + collect，原地删除满足条件的元素
        // caseInsensitiveCompare 返回 .orderedSame 表示忽略大小写相等
        repoHistoryCache.removeAll { $0.source.caseInsensitiveCompare(source) == .orderedSame }

        // 插入到最前面（最近使用的排最前）
        let now = ISO8601DateFormatter().string(from: Date())
        let entry = RepoHistoryEntry(source: source, sourceUrl: sourceUrl, scannedAt: now)
        repoHistoryCache.insert(entry, at: 0)

        // 最多保留 20 条（prefix 截取前 N 个元素，类似 Python 的 list[:20]）
        if repoHistoryCache.count > 20 {
            repoHistoryCache = Array(repoHistoryCache.prefix(20))
        }
    }

    /// 获取所有 repo scan 历史记录
    ///
    /// 返回按最近 scan 时间排序的列表（最新的在前），最多 20 条
    func getRepoHistory() -> [RepoHistoryEntry] {
        ensureLoaded()
        return repoHistoryCache
    }

    /// 将内存缓存写入磁盘
    ///
    /// 使用原子写入（.atomic）确保文件不会因中途崩溃而损坏：
    /// 先写到临时文件，成功后再 rename 替换原文件。
    /// 类似 Go 中先写 .tmp 文件再 os.Rename 的模式。
    func save() throws {
        // linkedSkillsCache 为空时存为 nil，JSON 中不输出该字段（保持简洁）
        // repoHistoryCache 为空时同理
        let cacheFile = CacheFile(
            skills: cache,
            linkedSkills: linkedSkillsCache.isEmpty ? nil : linkedSkillsCache,
            repoHistory: repoHistoryCache.isEmpty ? nil : repoHistoryCache
        )
        let encoder = JSONEncoder()
        // prettyPrinted 让 JSON 格式化输出，方便人类阅读和调试
        // sortedKeys 保证输出顺序一致，方便 git diff 查看变化
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(cacheFile)

        // 确保父目录存在（~/.agents/）
        let parentDir = filePath.deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        try data.write(to: filePath, options: .atomic)
    }

    // MARK: - Private Methods

    /// 确保缓存已从磁盘加载（懒加载模式）
    ///
    /// 首次调用时从磁盘读取，后续调用直接使用内存缓存。
    /// 如果文件不存在或解析失败，使用空字典（不抛错，降级处理）。
    private func ensureLoaded() {
        guard !isLoaded else { return }
        isLoaded = true

        let fm = FileManager.default
        guard fm.fileExists(atPath: filePath.path) else { return }

        do {
            let data = try Data(contentsOf: filePath)
            let cacheFile = try JSONDecoder().decode(CacheFile.self, from: data)
            cache = cacheFile.skills
            // 加载关联信息（可能为 nil，旧格式文件中没有此字段）
            linkedSkillsCache = cacheFile.linkedSkills ?? [:]
            // 加载 scan 历史记录（可能为 nil，旧格式文件中没有此字段）
            repoHistoryCache = cacheFile.repoHistory ?? []
        } catch {
            // 文件损坏或格式不兼容时，使用空缓存重新开始
            // 不抛错是因为缓存丢失不影响核心功能，只是需要重新 backfill
            cache = [:]
            linkedSkillsCache = [:]
            repoHistoryCache = []        }
    }
}
