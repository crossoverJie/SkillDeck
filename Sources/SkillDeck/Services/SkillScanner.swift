import Foundation

/// SkillScanner is responsible for scanning the file system to discover all installed skills
///
/// Scanning strategy:
/// 1. Scan the configured global skills directory as the only canonical source.
/// 2. Inspect the whole-directory links only to report each skill's synchronized tools.
///
/// This is similar to filepath.Walk in Go for traversing directory trees
actor SkillScanner {

    /// Shared global skills directory, resolved from the user's storage setting each time it is used.
    static var sharedSkillsURL: URL { SkillStorageSettings.globalSkillsURL }

    /// Scan the canonical global skills directory.
    /// - Returns: Skills owned by the configured global directory; agent directories never add independent entries.
    func scanAll() async throws -> [Skill] {
        scanDirectory(Self.sharedSkillsURL, scope: .sharedGlobal)
            .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
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
