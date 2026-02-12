import Foundation

/// LockFileManager 负责读写 .skill-lock.json 文件（F07）
///
/// lock file 是 skills 生态的中央注册表，记录了所有通过包管理器安装的 skill。
/// 文件位置：~/.agents/.skill-lock.json
///
/// 使用 actor 保证线程安全，因为多个操作可能同时读写 lock file
actor LockFileManager {

    /// lock file 的默认路径
    static let defaultPath: URL = {
        let home = NSString(string: "~/.agents/.skill-lock.json").expandingTildeInPath
        return URL(fileURLWithPath: home)
    }()

    /// 当前使用的 lock file 路径（可在测试中覆盖）
    let filePath: URL

    /// 内存中缓存的 lock file 数据
    private var cached: LockFile?

    init(filePath: URL = LockFileManager.defaultPath) {
        self.filePath = filePath
    }

    /// 读取并解析 lock file
    /// - Returns: LockFile 结构体
    /// - Throws: 文件读取或 JSON 解析错误
    ///
    /// JSONDecoder 是 Swift 内置的 JSON 反序列化器（类似 Go 的 json.Unmarshal）
    func read() throws -> LockFile {
        if let cached {
            return cached
        }

        let data = try Data(contentsOf: filePath)
        let decoder = JSONDecoder()
        let lockFile = try decoder.decode(LockFile.self, from: data)
        cached = lockFile
        return lockFile
    }

    /// 获取指定 skill 的 lock entry
    func getEntry(skillName: String) throws -> LockEntry? {
        let lockFile = try read()
        return lockFile.skills[skillName]
    }

    /// 更新指定 skill 的 lock entry
    /// 使用原子写入确保文件不会因中途崩溃而损坏
    func updateEntry(skillName: String, entry: LockEntry) throws {
        var lockFile = try read()
        lockFile.skills[skillName] = entry
        try write(lockFile)
    }

    /// 删除指定 skill 的 lock entry
    func removeEntry(skillName: String) throws {
        var lockFile = try read()
        lockFile.skills.removeValue(forKey: skillName)
        try write(lockFile)
    }

    /// 将 LockFile 写回磁盘
    /// 使用原子写入（.atomic 选项）：先写到临时文件，再 rename，保证不会写一半崩溃
    /// 这是文件写入的最佳实践，类似 Go 中先写 .tmp 文件再 os.Rename
    private func write(_ lockFile: LockFile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(lockFile)
        try data.write(to: filePath, options: .atomic)
        cached = lockFile
    }

    /// 清除内存缓存，强制下次从磁盘读取
    func invalidateCache() {
        cached = nil
    }

    /// 检查 lock file 是否存在
    var exists: Bool {
        FileManager.default.fileExists(atPath: filePath.path)
    }

    /// 如果 lock file 不存在则创建空文件（F10：首次通过 SkillDeck 安装时使用）
    ///
    /// 创建一个符合 version 3 格式的空 lock file，
    /// 后续的 updateEntry 可以直接在此基础上追加 skill 条目。
    /// 如果文件已存在则不做任何操作（幂等操作）。
    func createIfNotExists() throws {
        guard !exists else { return }

        // 确保父目录 (~/.agents/) 存在
        let parentDir = filePath.deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: parentDir.path) {
            // withIntermediateDirectories: true 类似 mkdir -p，递归创建目录
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        // 创建空的 lock file（version 3 格式，与 npx skills 工具兼容）
        let emptyLockFile = LockFile(
            version: 3,
            skills: [:],
            dismissed: [:],
            lastSelectedAgents: []
        )
        try write(emptyLockFile)
    }
}
