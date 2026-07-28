import Foundation

/// SymlinkManager provides filesystem inspection for whole-directory skill synchronization.
///
/// Core Concepts:
/// - The canonical directory is selected in SkillDeck settings.
/// - Each Agent can reference it through a single directory symlink.
///
/// symlink is similar to Linux/macOS `ln -s`, a special file pointing to another file/directory
enum SymlinkManager {

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
            // If already has direct installation, skip (direct installation has higher priority)
            guard !agentsWithDirectInstallation.contains(agentType) else {
                continue
            }

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

        return installations
    }
}
