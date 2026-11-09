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

    /// Shared global skills directory (delegates to AgentType.sharedSkillsDirectoryURL for single source of truth)
    static let sharedSkillsURL: URL = AgentType.sharedSkillsDirectoryURL

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

    /// Parse individual skill directory.
    ///
    /// A skill's content file can be in one of four states. We must keep disabled skills visible
    /// (for quick A/B toggling) and surface a "broken" row when the content disappears, instead
    /// of letting the skill silently vanish from the list:
    ///   1. `SKILL.md` present                 → active, parse it (`isDisabled = false`)
    ///   2. `.SKILL.md.disabled` present      → disabled, parse the marker (`isDisabled = true`)
    ///   3. neither, but a real shared dir   → broken (`isBroken = true`), global pass only
    ///   4. otherwise                        → not a skill, return nil
    ///
    /// `SkillDisableManager.skillContentURL(for:)` is used ONLY here to pick the file to read; it
    /// must never be used as a write target (see its doc comment).
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

        let skillMDURL = SkillDisableManager.skillMDURL(for: canonicalURL)
        let markerURL = SkillDisableManager.markerURL(for: canonicalURL)
        let hasSkillMD = fm.fileExists(atPath: skillMDURL.path)
        let hasMarker = fm.fileExists(atPath: markerURL.path)

        // The current readable content file (real SKILL.md wins over the marker). nil means there
        // is nothing to parse — either a broken skill or a non-skill directory.
        let contentURL = SkillDisableManager.skillContentURL(for: canonicalURL)

        let isDisabled: Bool
        let isBroken: Bool

        if hasSkillMD {
            // Branch 1: active skill.
            isDisabled = false
            isBroken = false
        } else if hasMarker {
            // Branch 2: disabled skill. Parsing the marker keeps displayName / description /
            // markdownBody available so the row still reads like a real skill.
            isDisabled = true
            isBroken = false
        } else if scope == .sharedGlobal {
            // Branch 3: no content file. Produce a visible "broken" row ONLY on the global scan
            // pass, so unrelated subdirectories inside agent folders never become ghost rows.
            // `fileExists(atPath:isDirectory:)` returns false for a dangling symlink, which is
            // exactly what we want (a broken symlink target must not produce a row). Using
            // resourceValues(.isDirectoryKey) would throw for dangling links and need `try?`.
            var isDir: ObjCBool = false
            let existsAsRealDirectory = fm.fileExists(atPath: canonicalURL.path, isDirectory: &isDir)
                && isDir.boolValue
            guard existsAsRealDirectory else {
                return nil
            }
            print("[SkillScanner] broken shared skill (no \(SkillDisableManager.skillFilename)/marker): \(canonicalURL.path)")
            isDisabled = false
            isBroken = true
        } else {
            // Branch 4: nothing to show for this scope.
            return nil
        }

        // Parse the content file when present; on parse failure use safe defaults so one bad file
        // never blocks the entire scan. Broken skills have no content to parse.
        let metadata: SkillMetadata
        let markdownBody: String
        if let contentURL {
            do {
                let result = try SkillMDParser.parse(fileURL: contentURL)
                metadata = result.metadata
                markdownBody = result.markdownBody
            } catch {
                metadata = SkillMetadata(name: skillName, description: "")
                markdownBody = ""
            }
        } else {
            metadata = SkillMetadata(name: skillName, description: "")
            markdownBody = ""
        }

        // Find installation information for this skill across all Agents.
        // This is unchanged: it follows symlinks with fileExists, so it still reports every
        // assignment even while the content file is renamed to the marker.
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
            lockEntry: nil,  // lock entry populated later by SkillManager
            isDisabled: isDisabled,
            isBroken: isBroken
        )
    }
}
