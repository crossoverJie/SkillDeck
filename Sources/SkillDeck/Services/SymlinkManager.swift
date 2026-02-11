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

    /// 解析 symlink 指向的真实路径（递归解析多级 symlink 链）
    ///
    /// 使用 URL.resolvingSymlinksInPath() 而非单级的 destinationOfSymbolicLink，
    /// 以正确处理多级 symlink 链。例如：
    ///   ~/.copilot/skills/foo → ~/.claude/skills/foo → ~/.agents/skills/foo
    /// resolvingSymlinksInPath() 会递归解析到最终的真实路径 ~/.agents/skills/foo
    ///
    /// 如果不是 symlink，返回原路径（标准化后）
    static func resolveSymlink(at url: URL) -> URL {
        // resolvingSymlinksInPath() 是 Foundation 提供的递归 symlink 解析方法，
        // 类似 Python 的 os.path.realpath() 或 Go 的 filepath.EvalSymlinks()
        // 它会一直跟随 symlink 直到找到最终的真实路径
        return url.resolvingSymlinksInPath()
    }

    /// 获取 skill 在所有 Agent 中的安装信息（含继承安装）
    ///
    /// 采用两遍扫描策略：
    /// 1. 第一遍：检查每个 Agent 自身 skills 目录下的直接安装
    /// 2. 第二遍：对于没有直接安装的 Agent，检查其 additionalReadableSkillsDirectories，
    ///    若找到则标记为继承安装（isInherited: true）
    ///
    /// 优先级规则：如果 Agent 在自身目录中已有该 skill（直接安装），则不再添加继承安装
    /// 例如 ~/.copilot/skills/foo 已存在，则不会再从 ~/.claude/skills/foo 继承
    static func findInstallations(skillName: String, canonicalURL: URL) -> [SkillInstallation] {
        var installations: [SkillInstallation] = []
        /// 记录哪些 Agent 已有直接安装，用于第二遍过滤
        /// Set 类似 Java 的 HashSet，用于 O(1) 查找
        var agentsWithDirectInstallation = Set<AgentType>()

        // ========== 第一遍：直接安装扫描 ==========
        for agentType in AgentType.allCases {
            // Codex 的 skillsDirectoryURL 是 ~/.agents/skills/（canonical 共享目录），
            // 不是独立的 Agent skills 目录。所有 canonical skill 都存储在那里，
            // 不应视为"已安装到 Codex"。与 SkillScanner.scanAll() 的处理保持一致。
            if agentType == .codex { continue }

            let skillURL = agentType.skillsDirectoryURL.appendingPathComponent(skillName)

            // 检查 skill 是否存在于该 Agent 的 skills 目录
            guard FileManager.default.fileExists(atPath: skillURL.path) else {
                continue
            }

            let isLink = isSymlink(at: skillURL)

            // 如果是 symlink，验证它最终指向的是同一个 canonical 位置
            // 使用 resolvingSymlinksInPath() 递归解析，处理多级 symlink 链
            if isLink {
                let resolved = resolveSymlink(at: skillURL)
                // standardized 会规范化路径（去除 .. 和 . 等）
                if resolved.standardized.path == canonicalURL.standardized.path {
                    installations.append(SkillInstallation(
                        agentType: agentType,
                        path: skillURL,
                        isSymlink: true
                    ))
                    agentsWithDirectInstallation.insert(agentType)
                }
            } else {
                // 不是 symlink，说明是原始文件（agent-local skill）
                installations.append(SkillInstallation(
                    agentType: agentType,
                    path: skillURL,
                    isSymlink: false
                ))
                agentsWithDirectInstallation.insert(agentType)
            }
        }

        // ========== 第二遍：继承安装扫描 ==========
        // 对于没有直接安装的 Agent，检查它能额外读取的其他 Agent 目录
        for agentType in AgentType.allCases {
            // Codex 跳过，原因同第一遍（canonical 共享目录不等于 Codex 独立安装）
            if agentType == .codex { continue }
            // 如果已有直接安装，跳过（直接安装优先级更高）
            guard !agentsWithDirectInstallation.contains(agentType) else { continue }

            // 遍历该 Agent 可额外读取的目录列表
            for additionalDir in agentType.additionalReadableSkillsDirectories {
                let skillURL = additionalDir.url.appendingPathComponent(skillName)

                guard FileManager.default.fileExists(atPath: skillURL.path) else {
                    continue
                }

                // 验证该路径（解析 symlink 后）确实指向同一个 canonical skill
                let resolved: URL
                if isSymlink(at: skillURL) {
                    resolved = resolveSymlink(at: skillURL)
                } else {
                    resolved = skillURL
                }

                if resolved.standardized.path == canonicalURL.standardized.path {
                    // 找到继承安装：skill 存在于源 Agent 目录中，当前 Agent 可以读取
                    installations.append(SkillInstallation(
                        agentType: agentType,
                        path: skillURL,
                        isSymlink: isSymlink(at: skillURL),
                        isInherited: true,
                        inheritedFrom: additionalDir.sourceAgent
                    ))
                    // 找到第一个匹配就停止（避免同一 Agent 重复添加继承安装）
                    break
                }
            }
        }

        // ========== 第三遍：Codex 特殊处理 ==========
        // Codex 直接从 ~/.agents/skills/ 读取用户级 skills，
        // 其 skillsDirectoryURL 与 canonical 共享目录相同。
        // 因此所有 canonical skill 天然对 Codex 可用，
        // 这里为 Codex 创建一个 isSymlink: false 的安装记录，
        // 使得 sidebar badge、dashboard 过滤等 UI 能正确显示 Codex 状态。
        let codexSkillURL = AgentType.codex.skillsDirectoryURL.appendingPathComponent(skillName)
        if FileManager.default.fileExists(atPath: codexSkillURL.path) {
            let resolved = resolveSymlink(at: codexSkillURL)
            // 验证路径确实指向同一个 canonical skill（防止巧合同名但不同路径的情况）
            if resolved.standardized.path == canonicalURL.standardized.path {
                installations.append(SkillInstallation(
                    agentType: .codex,
                    path: codexSkillURL,
                    isSymlink: false  // canonical 原始文件，不是 symlink
                ))
            }
        }

        return installations
    }
}
