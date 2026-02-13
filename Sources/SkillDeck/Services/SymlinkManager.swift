import Foundation

/// SymlinkManager is responsible for creating and removing symlinks (F06 Agent Assignment)
///
/// Core Concepts:
/// - The "real copy" of all skills is stored in ~/.agents/skills/ (canonical location)
/// - Each Agent references the shared skill via symlink
/// - Example: ~/.claude/skills/agent-notifier -> ~/.agents/skills/agent-notifier
///
/// symlink is similar to Linux/macOS `ln -s`, a special file pointing to another file/directory
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

    /// Create symlink for skill to specified Agent's skills directory
    ///
    /// - Parameters:
    ///   - source: canonical path of the skill (e.g. ~/.agents/skills/agent-notifier/)
    ///   - agent: target Agent type
    /// - Throws: SymlinkError
    ///
    /// Effect: agent.skillsDirectoryURL/skillName -> source
    static func createSymlink(from source: URL, to agent: AgentType) throws {
        let fm = FileManager.default
        let skillName = source.lastPathComponent
        let targetDir = agent.skillsDirectoryURL
        let targetURL = targetDir.appendingPathComponent(skillName)

        // 1. Verify source directory exists
        guard fm.fileExists(atPath: source.path) else {
            throw SymlinkError.sourceNotFound(source)
        }

        // 2. Ensure target Agent's skills directory exists, create if not
        if !fm.fileExists(atPath: targetDir.path) {
            // withIntermediateDirectories: true is similar to mkdir -p, creates parent directories recursively
            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }

        // 3. Check if target location already exists
        guard !fm.fileExists(atPath: targetURL.path) else {
            throw SymlinkError.targetAlreadyExists(targetURL)
        }

        // 4. Create symlink
        // createSymbolicLink is equivalent to ln -s source targetURL
        try fm.createSymbolicLink(at: targetURL, withDestinationURL: source)
    }

    /// Remove symlink of a skill under specified Agent
    ///
    /// - Parameters:
    ///   - skillName: skill directory name
    ///   - agent: Agent type
    /// - Throws: SymlinkError
    static func removeSymlink(skillName: String, from agent: AgentType) throws {
        let fm = FileManager.default
        let targetURL = agent.skillsDirectoryURL.appendingPathComponent(skillName)

        // Verify path is indeed a symlink to avoid deleting real directory by mistake
        guard isSymlink(at: targetURL) else {
            return // Not a symlink, return silently
        }

        do {
            try fm.removeItem(at: targetURL)
        } catch {
            throw SymlinkError.removalFailed(targetURL, error)
        }
    }

    /// Check if given path is a symlink
    ///
    /// FileManager.fileExists automatically resolves symlinks (follows links),
    /// so we need to use attributesOfItem to read file attributes directly to judge
    static func isSymlink(at url: URL) -> Bool {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let fileType = attrs[.type] as? FileAttributeType else {
            return false
        }
        return fileType == .typeSymbolicLink
    }

    /// Resolve real path pointed to by symlink (recursively resolve multi-level symlink chain)
    ///
    /// Use URL.resolvingSymlinksInPath() instead of single-level destinationOfSymbolicLink,
    /// to correctly handle multi-level symlink chains. Example:
    ///   ~/.copilot/skills/foo → ~/.claude/skills/foo → ~/.agents/skills/foo
    /// resolvingSymlinksInPath() will recursively resolve to the final real path ~/.agents/skills/foo
    ///
    /// If not a symlink, return original path (standardized)
    static func resolveSymlink(at url: URL) -> URL {
        // resolvingSymlinksInPath() is a recursive symlink resolution method provided by Foundation,
        // similar to Python's os.path.realpath() or Go's filepath.EvalSymlinks()
        // It will follow symlinks until the final real path is found
        return url.resolvingSymlinksInPath()
    }

    /// Get installation info of skill across all Agents (including inherited installations)
    ///
    /// Uses two-pass scan strategy:
    /// 1. First pass: Check direct installations under each Agent's own skills directory
    /// 2. Second pass: For Agents without direct installation, check their additionalReadableSkillsDirectories,
    ///    mark as inherited installation (isInherited: true) if found
    ///
    /// Priority rule: If Agent already has this skill in its own directory (direct installation), do not add inherited installation
    /// e.g. if ~/.copilot/skills/foo exists, do not inherit from ~/.claude/skills/foo
    static func findInstallations(skillName: String, canonicalURL: URL) -> [SkillInstallation] {
        var installations: [SkillInstallation] = []
        /// Record which Agents have direct installation, for second pass filtering
        /// Set is similar to Java's HashSet, used for O(1) lookup
        var agentsWithDirectInstallation = Set<AgentType>()

        // ========== First pass: Direct installation scan ==========
        for agentType in AgentType.allCases {
            // Codex's skillsDirectoryURL is ~/.agents/skills/ (canonical shared directory),
            // not an independent Agent skills directory. All canonical skills are stored there,
            // should not be considered "installed to Codex". Consistent with SkillScanner.scanAll() handling.
            if agentType == .codex { continue }

            let skillURL = agentType.skillsDirectoryURL.appendingPathComponent(skillName)

            // Check if skill exists in this Agent's skills directory
            guard FileManager.default.fileExists(atPath: skillURL.path) else {
                continue
            }

            let isLink = isSymlink(at: skillURL)

            // If it's a symlink, verify it ultimately points to the same canonical location
            // Use resolvingSymlinksInPath() to recursively resolve, handling multi-level symlink chains
            if isLink {
                let resolved = resolveSymlink(at: skillURL)
                // standardized normalizes path (removes .. and . etc)
                if resolved.standardized.path == canonicalURL.standardized.path {
                    installations.append(SkillInstallation(
                        agentType: agentType,
                        path: skillURL,
                        isSymlink: true
                    ))
                    agentsWithDirectInstallation.insert(agentType)
                }
            } else {
                // Not a symlink, means it's an original file (agent-local skill)
                installations.append(SkillInstallation(
                    agentType: agentType,
                    path: skillURL,
                    isSymlink: false
                ))
                agentsWithDirectInstallation.insert(agentType)
            }
        }

        // ========== Second pass: Inherited installation scan ==========
        // For Agents without direct installation, check other Agent directories it can additionally read
        for agentType in AgentType.allCases {
            // Codex skipped, reason same as first pass (canonical shared directory != Codex independent installation)
            if agentType == .codex { continue }
            // If already has direct installation, skip (direct installation has higher priority)
            guard !agentsWithDirectInstallation.contains(agentType) else { continue }

            // Iterate through list of directories this Agent can additionally read
            for additionalDir in agentType.additionalReadableSkillsDirectories {
                let skillURL = additionalDir.url.appendingPathComponent(skillName)

                guard FileManager.default.fileExists(atPath: skillURL.path) else {
                    continue
                }

                // Verify this path (after resolving symlink) indeed points to the same canonical skill
                let resolved: URL
                if isSymlink(at: skillURL) {
                    resolved = resolveSymlink(at: skillURL)
                } else {
                    resolved = skillURL
                }

                if resolved.standardized.path == canonicalURL.standardized.path {
                    // Inherited installation found: skill exists in source Agent directory, current Agent can read it
                    installations.append(SkillInstallation(
                        agentType: agentType,
                        path: skillURL,
                        isSymlink: isSymlink(at: skillURL),
                        isInherited: true,
                        inheritedFrom: additionalDir.sourceAgent
                    ))
                    // Stop on first match (avoid duplicate inherited installations for same Agent)
                    break
                }
            }
        }

        // ========== Third pass: Codex special handling ==========
        // Codex reads user-level skills directly from ~/.agents/skills/,
        // its skillsDirectoryURL is same as canonical shared directory.
        // Therefore all canonical skills are naturally available to Codex,
        // here create an isSymlink: false installation record for Codex,
        // so that sidebar badge, dashboard filtering etc. UI can correctly display Codex status.
        let codexSkillURL = AgentType.codex.skillsDirectoryURL.appendingPathComponent(skillName)
        if FileManager.default.fileExists(atPath: codexSkillURL.path) {
            let resolved = resolveSymlink(at: codexSkillURL)
            // Verify path indeed points to same canonical skill (prevent accidental same name but different path cases)
            if resolved.standardized.path == canonicalURL.standardized.path {
                installations.append(SkillInstallation(
                    agentType: .codex,
                    path: codexSkillURL,
                    isSymlink: false  // canonical original file, not a symlink
                ))
            }
        }

        return installations
    }
}
