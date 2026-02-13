import Foundation

/// SkillScanner is responsible for scanning the file system to discover all installed skills
///
/// Scanning strategy:
/// 1. First scan ~/.agents/skills/ (shared global directory)
/// 2. Then scan each Agent's skills directory
/// 3. Deduplicate via symlink resolution: if a skill in an Agent directory is a symlink to ~/.agents/skills/,
///    keep only one copy and record it in installations
///
/// This is similar to filepath.Walk in Go for traversing directory trees
actor SkillScanner {

    /// Shared global skills directory
    static let sharedSkillsURL: URL = {
        let path = NSString(string: "~/.agents/skills").expandingTildeInPath
        return URL(fileURLWithPath: path)
    }()

    /// Scan all skills, returning deduplicated results
    /// - Returns: Array of discovered skills (deduplicated, each skill name appears only once)
    func scanAll() async throws -> [Skill] {
        // Use skill id (directory name) as deduplication key, not canonicalURL.path
        // Reason: the same skill might be pointed to by different Agent symlinks to different physical paths
        // e.g. ~/.copilot/skills/agent-notifier -> /path/to/dev/agent-notifier
        //      ~/.agents/skills/agent-notifier   (another physical path)
        // Although canonicalURL is different, skill id is the same, should be treated as same skill
        var skillMap: [String: Skill] = [:]

        // 1. Scan shared global directory
        let globalSkills = scanDirectory(Self.sharedSkillsURL, scope: .sharedGlobal)
        for skill in globalSkills {
            skillMap[skill.id] = skill
        }

        // 2. Scan each Agent's skills directory
        for agentType in AgentType.allCases {
            // Codex uses shared directory, already scanned in step 1
            if agentType == .codex { continue }

            let agentSkills = scanDirectory(
                agentType.skillsDirectoryURL,
                scope: .agentLocal(agentType)
            )

            for skill in agentSkills {
                if var existingSkill = skillMap[skill.id] {
                    // Same name skill exists: merge installations (indicates same skill referenced by multiple Agents)
                    let newInstallations = skill.installations.filter { newInst in
                        !existingSkill.installations.contains(where: { $0.id == newInst.id })
                    }
                    existingSkill.installations.append(contentsOf: newInstallations)
                    // If previously agentLocal, now found referenced by other Agents, upgrade to sharedGlobal
                    if case .agentLocal = existingSkill.scope, existingSkill.installations.count > 1 {
                        existingSkill.scope = .sharedGlobal
                    }
                    skillMap[skill.id] = existingSkill
                } else {
                    // New skill: add directly
                    skillMap[skill.id] = skill
                }
            }
        }

        // Return sorted by name
        return skillMap.values.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    /// Scan all skills in a single directory
    /// - Parameters:
    ///   - directory: Directory URL to scan
    ///   - scope: Corresponding scope for this directory
    /// - Returns: Array of discovered skills
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

        // compactMap: transform each element, filtering out nil results (similar to Java Stream map + filter)
        return contents.compactMap { itemURL in
            parseSkillDirectory(itemURL, scope: scope)
        }
    }

    /// Parse individual skill directory
    /// - Returns: Skill instance, or nil if directory is not a valid skill
    private func parseSkillDirectory(_ url: URL, scope: SkillScope) -> Skill? {
        let fm = FileManager.default
        let skillName = url.lastPathComponent

        // Resolve symlink to get canonical path
        let canonicalURL: URL
        if SymlinkManager.isSymlink(at: url) {
            canonicalURL = SymlinkManager.resolveSymlink(at: url)
        } else {
            canonicalURL = url
        }

        // Check if SKILL.md exists
        let skillMDURL = canonicalURL.appendingPathComponent("SKILL.md")
        guard fm.fileExists(atPath: skillMDURL.path) else {
            return nil
        }

        // Parse SKILL.md
        let metadata: SkillMetadata
        let markdownBody: String
        do {
            let result = try SkillMDParser.parse(fileURL: skillMDURL)
            metadata = result.metadata
            markdownBody = result.markdownBody
        } catch {
            // Use default values on parse failure, do not block the entire scan
            metadata = SkillMetadata(name: skillName, description: "")
            markdownBody = ""
        }

        // Find installation information for this skill across all Agents
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
            lockEntry: nil  // lock entry populated later by SkillManager
        )
    }
}
