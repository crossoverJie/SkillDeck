import Foundation

/// SymlinkManager 负责创建和删除 symlink（F06 Agent Assignment）
///
/// 核心概念：
/// - 所有 skill 的「真实副本」存储在 ~/.agents/skills/（canonical location）
/// - 各 Agent 通过 symlink（符号链接）引用共享的 skill
/// - 例如：~/.claude/skills/agent-notifier -> ~/.agents/skills/agent-notifier
///
/// symlink 类似 Linux/macOS 的 `ln -s`，是一个指向另一个文件/目录的特殊文件
enum SymlinkManager {

    enum SymlinkError: Error, LocalizedError {
        case sourceNotFound(URL)
        case targetAlreadyExists(URL)
        case targetDirectoryNotFound(URL)
        case removalFailed(URL, Error)

        var errorDescription: String? {
            switch self {
            case .sourceNotFound(let url):
                "Skill source directory not found: \(url.path)"
            case .targetAlreadyExists(let url):
                "Target already exists: \(url.path)"
            case .targetDirectoryNotFound(let url):
                "Agent skills directory not found: \(url.path)"
            case .removalFailed(let url, let error):
                "Failed to remove symlink at \(url.path): \(error.localizedDescription)"
            }
        }
    }

    /// 为 skill 创建 symlink 到指定 Agent 的 skills 目录
    ///
    /// - Parameters:
    ///   - source: skill 的 canonical 路径（如 ~/.agents/skills/agent-notifier/）
    ///   - agent: 目标 Agent 类型
    /// - Throws: SymlinkError
    ///
    /// 效果：agent.skillsDirectoryURL/skillName -> source
    static func createSymlink(from source: URL, to agent: AgentType) throws {
        let fm = FileManager.default
        let skillName = source.lastPathComponent
        let targetDir = agent.skillsDirectoryURL
        let targetURL = targetDir.appendingPathComponent(skillName)

        // 1. 验证源目录存在
        guard fm.fileExists(atPath: source.path) else {
            throw SymlinkError.sourceNotFound(source)
        }

        // 2. 确保目标 Agent 的 skills 目录存在，不存在则创建
        if !fm.fileExists(atPath: targetDir.path) {
            // withIntermediateDirectories: true 类似 mkdir -p，会递归创建父目录
            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }

        // 3. 检查目标位置是否已存在
        guard !fm.fileExists(atPath: targetURL.path) else {
            throw SymlinkError.targetAlreadyExists(targetURL)
        }

        // 4. 创建 symlink
        // createSymbolicLink 等价于 ln -s source targetURL
        try fm.createSymbolicLink(at: targetURL, withDestinationURL: source)
    }

    /// 删除指定 Agent 下某个 skill 的 symlink
    ///
    /// - Parameters:
    ///   - skillName: skill 目录名
    ///   - agent: Agent 类型
    /// - Throws: SymlinkError
    static func removeSymlink(skillName: String, from agent: AgentType) throws {
        let fm = FileManager.default
        let targetURL = agent.skillsDirectoryURL.appendingPathComponent(skillName)

        // 验证路径确实是 symlink，避免误删真实目录
        guard isSymlink(at: targetURL) else {
            return // 不是 symlink，静默返回
        }

        do {
            try fm.removeItem(at: targetURL)
        } catch {
            throw SymlinkError.removalFailed(targetURL, error)
        }
    }

    /// 检查给定路径是否是 symlink
    ///
    /// FileManager.fileExists 会自动解析 symlink（跟随链接），
    /// 所以我们需要用 attributesOfItem 直接读取文件属性来判断
    static func isSymlink(at url: URL) -> Bool {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let fileType = attrs[.type] as? FileAttributeType else {
            return false
        }
        return fileType == .typeSymbolicLink
    }

    /// 解析 symlink 指向的真实路径
    /// 如果不是 symlink，返回原路径
    static func resolveSymlink(at url: URL) -> URL {
        let fm = FileManager.default
        guard let resolved = try? fm.destinationOfSymbolicLink(atPath: url.path) else {
            return url
        }
        // destinationOfSymbolicLink 返回的可能是相对路径，需要解析为绝对路径
        if resolved.hasPrefix("/") {
            return URL(fileURLWithPath: resolved)
        } else {
            return url.deletingLastPathComponent().appendingPathComponent(resolved).standardized
        }
    }

    /// 获取 skill 在所有 Agent 中的 symlink 安装信息
    static func findInstallations(skillName: String, canonicalURL: URL) -> [SkillInstallation] {
        var installations: [SkillInstallation] = []

        for agentType in AgentType.allCases {
            let skillURL = agentType.skillsDirectoryURL.appendingPathComponent(skillName)

            // 检查 skill 是否存在于该 Agent 的 skills 目录
            guard FileManager.default.fileExists(atPath: skillURL.path) else {
                continue
            }

            let isLink = isSymlink(at: skillURL)

            // 如果是 symlink，验证它指向的是同一个 canonical 位置
            if isLink {
                let resolved = resolveSymlink(at: skillURL)
                // standardized 会规范化路径（去除 .. 和 . 等）
                if resolved.standardized.path == canonicalURL.standardized.path {
                    installations.append(SkillInstallation(
                        agentType: agentType,
                        path: skillURL,
                        isSymlink: true
                    ))
                }
            } else {
                // 不是 symlink，说明是原始文件（agent-local skill）
                installations.append(SkillInstallation(
                    agentType: agentType,
                    path: skillURL,
                    isSymlink: false
                ))
            }
        }

        return installations
    }
}
