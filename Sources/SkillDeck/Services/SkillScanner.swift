import Foundation

/// SkillScanner 负责扫描文件系统，发现所有已安装的 skill
///
/// 扫描策略：
/// 1. 先扫描 ~/.agents/skills/（共享全局目录）
/// 2. 再扫描各 Agent 的 skills 目录
/// 3. 通过 symlink 解析去重：如果某个 Agent 目录下的 skill 是指向 ~/.agents/skills/ 的 symlink，
///    则只保留一份，并记录到 installations 中
///
/// 这类似于 Go 中遍历目录树的 filepath.Walk
actor SkillScanner {

    /// 共享全局 skills 目录
    static let sharedSkillsURL: URL = {
        let path = NSString(string: "~/.agents/skills").expandingTildeInPath
        return URL(fileURLWithPath: path)
    }()

    /// 扫描所有 skill，返回去重后的结果
    /// - Returns: 所有发现的 skill 数组（已去重，每个 skill 名称只出现一次）
    func scanAll() async throws -> [Skill] {
        // 用 skill id（目录名）作为去重 key，而不是 canonicalURL.path
        // 原因：同一个 skill 可能被不同 Agent 的 symlink 指向不同的物理路径
        // 例如 ~/.copilot/skills/agent-notifier -> /path/to/dev/agent-notifier
        //      ~/.agents/skills/agent-notifier   （另一个物理路径）
        // 虽然 canonicalURL 不同，但 skill id 相同，应视为同一个 skill
        var skillMap: [String: Skill] = [:]

        // 1. 扫描共享全局目录
        let globalSkills = scanDirectory(Self.sharedSkillsURL, scope: .sharedGlobal)
        for skill in globalSkills {
            skillMap[skill.id] = skill
        }

        // 2. 扫描每个 Agent 的 skills 目录
        for agentType in AgentType.allCases {
            // Codex 使用共享目录，已经在步骤 1 扫描过了
            if agentType == .codex { continue }

            let agentSkills = scanDirectory(
                agentType.skillsDirectoryURL,
                scope: .agentLocal(agentType)
            )

            for skill in agentSkills {
                if var existingSkill = skillMap[skill.id] {
                    // 已存在同名 skill：合并 installations（说明同一个 skill 被多个 Agent 引用）
                    let newInstallations = skill.installations.filter { newInst in
                        !existingSkill.installations.contains(where: { $0.id == newInst.id })
                    }
                    existingSkill.installations.append(contentsOf: newInstallations)
                    // 如果之前是 agentLocal，现在发现被其他 Agent 引用，升级为 sharedGlobal
                    if case .agentLocal = existingSkill.scope, existingSkill.installations.count > 1 {
                        existingSkill.scope = .sharedGlobal
                    }
                    skillMap[skill.id] = existingSkill
                } else {
                    // 新 skill：直接添加
                    skillMap[skill.id] = skill
                }
            }
        }

        // 按名称排序返回
        return skillMap.values.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    /// 扫描单个目录下的所有 skill
    /// - Parameters:
    ///   - directory: 要扫描的目录 URL
    ///   - scope: 这个目录对应的 scope
    /// - Returns: 发现的 skill 数组
    private func scanDirectory(_ directory: URL, scope: SkillScope) -> [Skill] {
        let fm = FileManager.default

        guard fm.fileExists(atPath: directory.path) else {
            return []
        }

        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        // compactMap: 对每个元素执行变换，过滤掉 nil 结果（类似 Java Stream 的 map + filter）
        return contents.compactMap { itemURL in
            parseSkillDirectory(itemURL, scope: scope)
        }
    }

    /// 解析单个 skill 目录
    /// - Returns: Skill 实例，如果目录不是有效的 skill 则返回 nil
    private func parseSkillDirectory(_ url: URL, scope: SkillScope) -> Skill? {
        let fm = FileManager.default
        let skillName = url.lastPathComponent

        // 解析 symlink，获取 canonical 路径
        let canonicalURL: URL
        if SymlinkManager.isSymlink(at: url) {
            canonicalURL = SymlinkManager.resolveSymlink(at: url)
        } else {
            canonicalURL = url
        }

        // 检查是否包含 SKILL.md
        let skillMDURL = canonicalURL.appendingPathComponent("SKILL.md")
        guard fm.fileExists(atPath: skillMDURL.path) else {
            return nil
        }

        // 解析 SKILL.md
        let metadata: SkillMetadata
        let markdownBody: String
        do {
            let result = try SkillMDParser.parse(fileURL: skillMDURL)
            metadata = result.metadata
            markdownBody = result.markdownBody
        } catch {
            // 解析失败时使用默认值，不阻断整个扫描
            metadata = SkillMetadata(name: skillName, description: "")
            markdownBody = ""
        }

        // 查找该 skill 在所有 Agent 中的安装信息
        let installations = SymlinkManager.findInstallations(
            skillName: skillName,
            canonicalURL: canonicalURL
        )

        return Skill(
            id: skillName,
            canonicalURL: canonicalURL,
            metadata: metadata,
            markdownBody: markdownBody,
            scope: scope,
            installations: installations,
            lockEntry: nil  // lock entry 稍后由 SkillManager 填充
        )
    }
}
