import Foundation

/// GitService 封装所有 git CLI 操作，是 F10（一键安装）和 F12（更新检查）的核心基础设施
///
/// 使用 `actor` 类型保证线程安全，因为 git 操作涉及临时目录和文件系统读写，
/// actor 保证同一时间只有一个任务在执行 git 命令，避免数据竞争。
/// actor 类似 Go 中的 goroutine + channel 模式，但由编译器保证安全性。
///
/// 设计模式：复用 AgentDetector 中已验证的 Process API 模式来执行外部命令
actor GitService {

    // MARK: - Error Types

    /// Git 操作相关错误
    /// LocalizedError 协议提供人类可读的错误描述（类似 Java 的 getMessage()）
    enum GitError: Error, LocalizedError {
        /// 系统中未安装 git
        case gitNotInstalled
        /// git clone 失败，附带错误信息
        case cloneFailed(String)
        /// 无效的仓库 URL 格式
        case invalidRepoURL(String)
        /// 无法获取 tree hash（git rev-parse 失败）
        case hashResolutionFailed(String)

        var errorDescription: String? {
            switch self {
            case .gitNotInstalled:
                "Git is not installed. Please install git to use this feature."
            case .cloneFailed(let message):
                "Failed to clone repository: \(message)"
            case .invalidRepoURL(let url):
                "Invalid repository URL: \(url)"
            case .hashResolutionFailed(let message):
                "Failed to resolve tree hash: \(message)"
            }
        }
    }

    // MARK: - Data Types

    /// 在远程仓库中发现的 skill 信息
    /// Identifiable 协议让 SwiftUI 的 ForEach 可以直接遍历（需要 id 属性）
    struct DiscoveredSkill: Identifiable {
        /// 唯一标识符：skill 目录名，如 "find-skills"
        let id: String
        /// 仓库内相对路径，如 "skills/find-skills"
        let folderPath: String
        /// SKILL.md 在仓库内的相对路径，如 "skills/find-skills/SKILL.md"
        let skillMDPath: String
        /// 解析出的 SKILL.md 元数据
        let metadata: SkillMetadata
        /// SKILL.md 的 markdown 正文
        let markdownBody: String
    }

    // MARK: - Public Methods

    /// 检查系统中是否安装了 git
    /// 通过 `which git` 命令检测，退出码 0 表示已安装
    func checkGitAvailable() async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["git"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// 克隆仓库到临时目录，支持浅克隆和完整克隆
    ///
    /// - Parameters:
    ///   - repoURL: 完整的仓库 URL（如 "https://github.com/vercel-labs/skills.git"）
    ///   - shallow: true 使用 `--depth 1` 浅克隆（只下载最新一次 commit，速度快）；
    ///              false 执行完整克隆（包含全部 git 历史，用于 commit hash backfill）
    /// - Returns: 克隆后的本地临时目录 URL
    /// - Throws: GitError.gitNotInstalled 或 GitError.cloneFailed
    ///
    /// 浅克隆 `--depth 1` 类似 Go 中 go-git 的 Depth: 1 选项。
    /// 完整克隆需要更多时间和空间，但可以访问 git 历史记录。
    func cloneRepo(repoURL: String, shallow: Bool) async throws -> URL {
        // 创建临时目录：/tmp/SkillDeck-<UUID>/
        // UUID 保证每次克隆使用不同的目录，避免冲突
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillDeck-\(UUID().uuidString)")

        // 根据 shallow 参数决定克隆深度
        var arguments = ["clone"]
        if shallow {
            arguments += ["--depth", "1"]
        }
        arguments += [repoURL, tempDir.path]

        let output = try await runGitCommand(
            arguments: arguments,
            workingDirectory: nil
        )

        // 验证克隆是否成功（目录是否存在）
        guard FileManager.default.fileExists(atPath: tempDir.path) else {
            throw GitError.cloneFailed(output)
        }

        return tempDir
    }

    /// 浅克隆仓库的便捷方法（保持 API 兼容）
    ///
    /// 内部调用 `cloneRepo(shallow: true)`，等价于 `git clone --depth 1`
    func shallowClone(repoURL: String) async throws -> URL {
        try await cloneRepo(repoURL: repoURL, shallow: true)
    }

    /// 获取仓库 HEAD 的 commit hash（完整 40 字符 SHA-1）
    ///
    /// - Parameter repoDir: 仓库的本地目录
    /// - Returns: 完整的 commit hash 字符串（如 "abc123def456..."，40 字符）
    /// - Throws: GitError.hashResolutionFailed
    ///
    /// `git rev-parse HEAD` 返回当前分支最新 commit 的完整 SHA-1 hash。
    /// 注意：这是 **commit hash**，不是 tree hash。
    /// commit hash 标识一次提交，tree hash 标识文件夹内容快照。
    /// GitHub compare URL 需要 commit hash 才能正确跳转。
    func getCommitHash(in repoDir: URL) async throws -> String {
        let output = try await runGitCommand(
            arguments: ["rev-parse", "HEAD"],
            workingDirectory: repoDir
        )
        let hash = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty else {
            throw GitError.hashResolutionFailed("Empty commit hash")
        }
        return hash
    }

    /// 从 git 历史中搜索产生指定 tree hash 的 commit（用于 backfill 老 skill 的 commit hash）
    ///
    /// - Parameters:
    ///   - treeHash: 要匹配的 tree hash（来自 lockEntry.skillFolderHash）
    ///   - folderPath: skill 在仓库中的相对路径（如 "skills/find-skills"）
    ///   - repoDir: 完整克隆的仓库目录（必须包含 git 历史，不能是 shallow clone）
    /// - Returns: 匹配的 commit hash，未找到时返回 nil
    ///
    /// 实现原理：
    /// 1. `git log --format=%H -- <folderPath>` 获取所有修改过该路径的 commit 列表
    /// 2. 逐个执行 `git rev-parse <commit>:<folderPath>` 获取该 commit 下的 tree hash
    /// 3. 与目标 treeHash 对比，找到匹配的就返回对应的 commit hash
    ///
    /// 这个方法较慢（可能需要多次 git 调用），仅在 CommitHashCache 中没有缓存时调用，
    /// 结果会被缓存到 `~/.agents/.skilldeck-cache.json` 中，后续不会重复搜索。
    func findCommitForTreeHash(
        treeHash: String, folderPath: String, in repoDir: URL
    ) async throws -> String? {
        // 1. 获取所有修改过该路径的 commit 列表
        // --format=%H 只输出 commit hash（每行一个），不含其他信息
        let logOutput = try await runGitCommand(
            arguments: ["log", "--format=%H", "--", folderPath],
            workingDirectory: repoDir
        )

        // 按行分割得到 commit hash 列表
        let commits = logOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .map(String.init)

        // 2. 逐个检查每个 commit 下该路径的 tree hash
        for commit in commits {
            do {
                let output = try await runGitCommand(
                    arguments: ["rev-parse", "\(commit):\(folderPath)"],
                    workingDirectory: repoDir
                )
                let hash = output.trimmingCharacters(in: .whitespacesAndNewlines)
                // 3. 找到匹配的 tree hash，返回对应的 commit hash
                if hash == treeHash {
                    return commit
                }
            } catch {
                // 某些 commit 可能不包含该路径（例如路径被重命名之前的 commit），跳过
                continue
            }
        }

        // 遍历完所有 commit 都未找到匹配
        return nil
    }

    /// 获取指定路径的 git tree hash
    ///
    /// - Parameters:
    ///   - path: 仓库内的相对路径（如 "skills/find-skills"）
    ///   - repoDir: 仓库的本地目录
    /// - Returns: tree hash 字符串（如 "abc123def..."）
    /// - Throws: GitError.hashResolutionFailed
    ///
    /// `git rev-parse HEAD:<path>` 获取指定路径在 HEAD commit 中的 tree hash，
    /// 这个 hash 会在路径下任何文件发生变化时改变，用于检测更新。
    /// 类似 Go 中 go-git 的 tree.Hash
    func getTreeHash(for path: String, in repoDir: URL) async throws -> String {
        let output = try await runGitCommand(
            arguments: ["rev-parse", "HEAD:\(path)"],
            workingDirectory: repoDir
        )
        let hash = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty else {
            throw GitError.hashResolutionFailed("Empty hash for path: \(path)")
        }
        return hash
    }

    /// 扫描克隆的仓库目录，发现所有包含 SKILL.md 的 skill
    ///
    /// - Parameter repoDir: 克隆仓库的本地目录
    /// - Returns: 所有发现的 skill 数组
    ///
    /// 递归遍历仓库目录树，找到包含 SKILL.md 的目录，
    /// 并用 SkillMDParser 解析元数据。类似 Go 的 filepath.Walk。
    func scanSkillsInRepo(repoDir: URL) -> [DiscoveredSkill] {
        let fm = FileManager.default
        var discovered: [DiscoveredSkill] = []

        // enumerator 递归遍历目录树（类似 Python 的 os.walk 或 Go 的 filepath.Walk）
        // includingPropertiesForKeys 预取文件属性，提高性能
        guard let enumerator = fm.enumerator(
            at: repoDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]  // 跳过 .git 等隐藏目录
        ) else {
            return []
        }

        // 收集所有 SKILL.md 文件的路径
        var skillMDURLs: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.lastPathComponent == "SKILL.md" {
                skillMDURLs.append(fileURL)
            }
        }

        // 解析每个 SKILL.md
        for skillMDURL in skillMDURLs {
            let skillDir = skillMDURL.deletingLastPathComponent()
            let skillName = skillDir.lastPathComponent

            // 计算相对于仓库根目录的路径
            // 例如 repoDir = /tmp/xxx/, skillDir = /tmp/xxx/skills/find-skills/
            // → folderPath = "skills/find-skills"
            let repoDirPath = repoDir.standardizedFileURL.path
            let skillDirPath = skillDir.standardizedFileURL.path
            let folderPath: String
            if skillDirPath.hasPrefix(repoDirPath) {
                // dropFirst 去掉前缀路径和开头的 "/"
                var relative = String(skillDirPath.dropFirst(repoDirPath.count))
                // 移除开头的 "/" 如果有的话
                if relative.hasPrefix("/") {
                    relative = String(relative.dropFirst())
                }
                // 移除末尾的 "/" 如果有的话
                if relative.hasSuffix("/") {
                    relative = String(relative.dropLast())
                }
                folderPath = relative
            } else {
                folderPath = skillName
            }

            let skillMDPath = folderPath.isEmpty
                ? "SKILL.md"
                : "\(folderPath)/SKILL.md"

            // 用 SkillMDParser 解析 SKILL.md 内容
            do {
                let result = try SkillMDParser.parse(fileURL: skillMDURL)
                discovered.append(DiscoveredSkill(
                    id: skillName,
                    folderPath: folderPath,
                    skillMDPath: skillMDPath,
                    metadata: result.metadata,
                    markdownBody: result.markdownBody
                ))
            } catch {
                // 解析失败时使用目录名作为 fallback，不阻断整个扫描
                discovered.append(DiscoveredSkill(
                    id: skillName,
                    folderPath: folderPath,
                    skillMDPath: skillMDPath,
                    metadata: SkillMetadata(name: skillName, description: ""),
                    markdownBody: ""
                ))
            }
        }

        // 按名称排序
        return discovered.sorted { $0.id.lowercased() < $1.id.lowercased() }
    }

    /// 清理临时目录
    /// 在安装完成或取消后调用，释放磁盘空间
    func cleanupTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - URL Normalization（静态方法，无需 actor 隔离）

    /// 从 git 仓库 URL 生成 GitHub 网页 URL
    ///
    /// - Parameter sourceUrl: git 仓库 URL（如 "https://github.com/owner/repo.git"）
    /// - Returns: GitHub 网页 URL（如 "https://github.com/owner/repo"），非 GitHub URL 返回 nil
    ///
    /// `nonisolated` 表示不需要 actor 隔离，因为是纯函数不访问可变状态。
    /// 类似 Java 的 static 方法，可以在任意线程调用无需 await。
    nonisolated static func githubWebURL(from sourceUrl: String) -> String? {
        // 只处理 GitHub URL
        guard sourceUrl.lowercased().contains("github.com") else { return nil }

        var url = sourceUrl
        // 移除 .git 后缀
        if url.hasSuffix(".git") {
            url = String(url.dropLast(4))
        }
        // 移除末尾的 /
        if url.hasSuffix("/") {
            url = String(url.dropLast())
        }
        return url
    }

    /// 规范化仓库 URL 输入，支持多种格式
    ///
    /// 支持的输入格式：
    /// - `owner/repo`（如 "vercel-labs/skills"）→ 自动补全为 GitHub URL
    /// - `https://github.com/owner/repo`（完整 HTTPS URL）
    /// - `https://github.com/owner/repo.git`（带 .git 后缀）
    ///
    /// - Parameter input: 用户输入的仓库地址
    /// - Returns: 元组 (完整 repoURL, 显示用的 source 标识)
    /// - Throws: GitError.invalidRepoURL
    ///
    /// `nonisolated` 关键字表示这个方法不需要 actor 的隔离保护，
    /// 因为它是纯函数（pure function），不访问 actor 的任何可变状态。
    /// 类似 Java 的 static 方法 —— 可以在任意线程调用，无需 await。
    nonisolated static func normalizeRepoURL(_ input: String) throws -> (repoURL: String, source: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw GitError.invalidRepoURL(input)
        }

        // 情况 1：完整的 HTTPS URL（以 https:// 开头）
        if trimmed.lowercased().hasPrefix("https://") {
            // 从 URL 中提取 owner/repo 作为 source
            // 例如 "https://github.com/vercel-labs/skills.git" → "vercel-labs/skills"
            var source = trimmed
            // 移除 "https://github.com/" 前缀
            if let range = source.range(of: "https://github.com/", options: .caseInsensitive) {
                source = String(source[range.upperBound...])
            }
            // 移除 .git 后缀
            if source.hasSuffix(".git") {
                source = String(source.dropLast(4))
            }
            // 移除末尾的 /
            if source.hasSuffix("/") {
                source = String(source.dropLast())
            }

            // 确保 repoURL 以 .git 结尾
            var repoURL = trimmed
            if !repoURL.hasSuffix(".git") {
                // 移除末尾的 /
                if repoURL.hasSuffix("/") {
                    repoURL = String(repoURL.dropLast())
                }
                repoURL += ".git"
            }

            return (repoURL: repoURL, source: source)
        }

        // 情况 2：owner/repo 格式（如 "vercel-labs/skills"）
        // 验证格式：必须包含恰好一个 "/"
        let components = trimmed.split(separator: "/")
        guard components.count == 2,
              !components[0].isEmpty,
              !components[1].isEmpty else {
            throw GitError.invalidRepoURL(input)
        }

        // 移除 repo 名称中可能存在的 .git 后缀
        var repoName = String(components[1])
        if repoName.hasSuffix(".git") {
            repoName = String(repoName.dropLast(4))
        }

        let source = "\(components[0])/\(repoName)"
        let repoURL = "https://github.com/\(source).git"
        return (repoURL: repoURL, source: source)
    }

    // MARK: - Private Methods

    /// 执行 git 命令并返回 stdout 输出
    ///
    /// - Parameters:
    ///   - arguments: git 命令参数（不包含 "git" 本身）
    ///   - workingDirectory: 工作目录（nil 表示使用默认目录）
    /// - Returns: 命令的 stdout 输出
    /// - Throws: GitError
    ///
    /// 使用 Process API（类似 Java 的 ProcessBuilder 或 Go 的 exec.Command）
    /// 复用 AgentDetector 中已验证的 Process 执行模式
    private func runGitCommand(arguments: [String], workingDirectory: URL?) async throws -> String {
        // 先查找 git 的完整路径（通过 which git）
        let gitPath = try await findGitPath()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = arguments

        // 设置工作目录（如果指定）
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        // Pipe 用于捕获命令输出（类似 Go 的 exec.Command().Output()）
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw GitError.cloneFailed(error.localizedDescription)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        // 非 0 退出码表示命令执行失败
        guard process.terminationStatus == 0 else {
            let errorMessage = stderr.isEmpty ? stdout : stderr
            throw GitError.cloneFailed(errorMessage.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return stdout
    }

    /// 查找 git 可执行文件的完整路径
    /// 优先检查常用路径，避免每次都执行 which 命令
    private func findGitPath() async throws -> String {
        // 常见的 git 安装路径
        let commonPaths = [
            "/usr/bin/git",
            "/usr/local/bin/git",
            "/opt/homebrew/bin/git"
        ]

        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // 如果常见路径都找不到，通过 which 命令查找
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["git"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw GitError.gitNotInstalled
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !path.isEmpty else {
                throw GitError.gitNotInstalled
            }
            return path
        } catch is GitError {
            throw GitError.gitNotInstalled
        } catch {
            throw GitError.gitNotInstalled
        }
    }
}
