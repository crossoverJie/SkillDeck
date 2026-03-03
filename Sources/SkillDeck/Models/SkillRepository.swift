import Foundation

/// SkillRepository represents a user-configured Git repository as a custom Skills source.
///
/// Supports both SSH and HTTPS+PAT authentication.
/// - SSH reuses the system `~/.ssh` configuration
/// - HTTPS tokens are stored in macOS Keychain (not persisted in JSON config)
///
/// Two repository structures are supported:
/// - monorepo: One repo contains multiple skills in subdirectories (each with SKILL.md)
/// - singleSkill: Repo root contains a SKILL.md (equivalent to a single skill)
///
/// Conforms to Codable for JSON serialization to `~/.agents/.skilldeck-repos.json`.
/// Conforms to Identifiable so SwiftUI's ForEach can use it directly.
struct SkillRepository: Codable, Identifiable, Hashable {

    // MARK: - Nested Types

    /// Git hosting platform — determines default SSH hostname and icon
    enum Platform: String, Codable, CaseIterable {
        case github
        case gitlab

        /// Human-readable display name
        var displayName: String {
            switch self {
            case .github: "GitHub"
            case .gitlab: "GitLab"
            }
        }

        /// SF Symbol icon name for this platform
        var iconName: String {
            switch self {
            case .github: "number.circle"
            case .gitlab: "triangle.circle"
            }
        }

        /// Default SSH hostname for constructing/detecting URLs
        var sshHostname: String {
            switch self {
            case .github: "github.com"
            case .gitlab: "gitlab.com"
            }
        }
    }

    /// Authentication mode used for git clone/pull.
    enum AuthType: String, Codable, CaseIterable {
        case ssh
        case httpsToken

        var displayName: String {
            switch self {
            case .ssh: "SSH"
            case .httpsToken: "HTTPS + Token"
            }
        }

        static func infer(from repoURL: String) -> AuthType {
            let lowered = repoURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lowered.hasPrefix("git@") || lowered.hasPrefix("ssh://") {
                return .ssh
            }
            return .httpsToken
        }
    }

    /// Sync status for a repository (used transiently in UI, not persisted)
    enum SyncStatus: Equatable {
        case idle
        case syncing
        case success(Date)
        case error(String)
    }

    // MARK: - Persisted Properties

    /// Stable unique identifier — used as the key in ContentView's VM dictionary and SidebarItem
    let id: UUID

    /// User-facing display name, e.g. "team-skills"
    var name: String

    /// Git clone URL.
    /// - SSH example: git@github.com:org/repo.git
    /// - HTTPS example: https://github.com/org/repo.git
    /// This URL is passed directly to `git clone` / `git pull`.
    var repoURL: String

    /// Authentication mode for this repository.
    var authType: AuthType

    /// Git hosting platform (GitHub or GitLab)
    var platform: Platform

    /// Whether this repository is active. Disabled repos are not auto-synced on startup.
    var isEnabled: Bool

    /// Timestamp of the most recent successful sync (nil = never synced)
    var lastSyncedAt: Date?

    /// Directory name derived from the SSH URL, used as the local clone directory.
    /// Example: "git@github.com:org/team-skills.git" → "org-team-skills"
    /// Stored explicitly so it never changes even if the user renames the repo config.
    var localSlug: String

    /// Optional username used for HTTPS token auth (e.g. "git", "oauth2", or enterprise account).
    /// Not used for SSH repositories.
    var httpUsername: String?

    /// Keychain lookup key for HTTPS tokens (token itself is not stored in JSON).
    /// Usually the repository UUID string.
    var credentialKey: String?

    /// Whether hidden directories/files should be scanned for SKILL.md in this repository.
    ///
    /// Default is false to reduce ambiguity from duplicated hidden mirror directories.
    var scanHiddenPaths: Bool = false

    // MARK: - Computed Properties

    /// Full local path to the cloned repository directory.
    /// Expands tilde so Swift's FileManager can use it directly.
    /// Pattern: ~/.agents/repos/<localSlug>/
    var localPath: String {
        let base = NSString(string: "~/.agents/repos").expandingTildeInPath
        return "\(base)/\(localSlug)"
    }

    /// Whether the repository has been cloned locally (directory exists)
    var isCloned: Bool {
        FileManager.default.fileExists(atPath: localPath)
    }
}

// MARK: - SkillRepository Extension: URL Parsing

extension SkillRepository {

    /// Derive a filesystem-safe slug from repository URL.
    ///
    /// Examples:
    /// - "git@github.com:org/team-skills.git" → "org-team-skills"
    /// - "https://github.com/org/team-skills.git" → "org-team-skills"
    /// - "git@gitlab.com:myuser/private-repo.git" → "myuser-private-repo"
    ///
    /// Algorithm: extract the `org/repo` path component, replace "/" with "-", strip ".git".
    static func slugFrom(repoURL: String) -> String {
        let trimmed = repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var pathPart = trimmed

        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://"),
           let components = URLComponents(string: trimmed), !components.path.isEmpty {
            pathPart = components.path
        } else if trimmed.lowercased().hasPrefix("git@") {
            if let colonIdx = trimmed.firstIndex(of: ":") {
                pathPart = String(trimmed[trimmed.index(after: colonIdx)...])
            }
        }

        while pathPart.hasPrefix("/") {
            pathPart = String(pathPart.dropFirst())
        }
        while pathPart.hasSuffix("/") {
            pathPart = String(pathPart.dropLast())
        }
        if pathPart.hasSuffix(".git") {
            pathPart = String(pathPart.dropLast(4))
        }

        let slug = pathPart.replacingOccurrences(of: "/", with: "-")
        if !slug.isEmpty {
            return slug
        }

        // Fallback: keep only alnum + dash + underscore.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return trimmed.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
    }

    /// Detect platform from repository URL hostname.
    ///
    /// "git@github.com:..." or "https://github.com/..." → .github
    /// "git@gitlab.com:..." or "https://gitlab.com/..." → .gitlab
    /// Falls back to .github for unknown hostnames.
    static func platformFrom(repoURL: String) -> Platform {
        let lower = repoURL.lowercased()
        if lower.contains("gitlab.com") { return .gitlab }
        return .github
    }

    /// Validate repository URL format based on selected auth mode.
    ///
    /// Returns nil if valid, or an error description string if invalid.
    static func validate(repoURL: String, authType: AuthType) -> String? {
        let trimmed = repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Repository URL cannot be empty" }

        switch authType {
        case .ssh:
            guard trimmed.contains("@"), trimmed.contains(":") else {
                return "Invalid SSH URL format. Expected: git@hostname:org/repo.git"
            }
            if let colonIdx = trimmed.firstIndex(of: ":") {
                let path = String(trimmed[trimmed.index(after: colonIdx)...])
                guard path.contains("/") else {
                    return "Invalid SSH URL: path must include org/repo"
                }
            }
            return nil
        case .httpsToken:
            guard trimmed.lowercased().hasPrefix("https://") else {
                return "HTTPS URL must start with https://"
            }
            guard let components = URLComponents(string: trimmed),
                  components.host != nil else {
                return "Invalid HTTPS URL"
            }
            let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard path.contains("/") else {
                return "Invalid HTTPS URL: path must include org/repo"
            }
            return nil
        }
    }

    /// Convert repository URL to the desired authentication scheme while preserving host and path.
    ///
    /// Examples:
    /// - git@github.com:org/repo.git -> https://github.com/org/repo.git
    /// - https://gitlab.com/org/repo.git -> git@gitlab.com:org/repo.git
    ///
    /// Returns the original value unchanged when URL format cannot be parsed safely.
    static func convertRepoURL(_ repoURL: String, to authType: AuthType) -> String {
        let trimmed = repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard let parsed = parseHostAndPath(from: trimmed) else { return trimmed }

        switch authType {
        case .ssh:
            return "git@\(parsed.host):\(parsed.path).git"
        case .httpsToken:
            return "https://\(parsed.host)/\(parsed.path).git"
        }
    }

    /// Parse host/path from SSH/HTTPS repository URL formats used by SkillDeck.
    private static func parseHostAndPath(from repoURL: String) -> (host: String, path: String)? {
        let lower = repoURL.lowercased()
        var host: String?
        var path: String?

        if lower.hasPrefix("git@") {
            let withoutPrefix = String(repoURL.dropFirst(4))
            let parts = withoutPrefix.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { return nil }
            host = String(parts[0])
            path = String(parts[1])
        } else if lower.hasPrefix("ssh://") || lower.hasPrefix("https://") {
            guard let components = URLComponents(string: repoURL),
                  let parsedHost = components.host else {
                return nil
            }
            host = parsedHost
            path = components.path
        } else {
            return nil
        }

        guard let host, var path else { return nil }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(".git") {
            path = String(path.dropLast(4))
        }
        guard !host.isEmpty, !path.isEmpty, path.contains("/") else {
            return nil
        }
        return (host, path)
    }
}

// MARK: - Codable Backward Compatibility

extension SkillRepository {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case repoURL
        case sshURL // legacy key
        case authType
        case platform
        case isEnabled
        case lastSyncedAt
        case localSlug
        case httpUsername
        case credentialKey
        case scanHiddenPaths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let repoURL = try container.decodeIfPresent(String.self, forKey: .repoURL)
            ?? container.decode(String.self, forKey: .sshURL)

        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.repoURL = repoURL
        self.authType = try container.decodeIfPresent(AuthType.self, forKey: .authType)
            ?? AuthType.infer(from: repoURL)
        self.platform = try container.decode(Platform.self, forKey: .platform)
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        self.lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        self.localSlug = try container.decode(String.self, forKey: .localSlug)
        self.httpUsername = try container.decodeIfPresent(String.self, forKey: .httpUsername)
        self.credentialKey = try container.decodeIfPresent(String.self, forKey: .credentialKey)
        self.scanHiddenPaths = try container.decodeIfPresent(Bool.self, forKey: .scanHiddenPaths) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(repoURL, forKey: .repoURL)
        try container.encode(authType, forKey: .authType)
        try container.encode(platform, forKey: .platform)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(lastSyncedAt, forKey: .lastSyncedAt)
        try container.encode(localSlug, forKey: .localSlug)
        try container.encodeIfPresent(httpUsername, forKey: .httpUsername)
        try container.encodeIfPresent(credentialKey, forKey: .credentialKey)
        try container.encode(scanHiddenPaths, forKey: .scanHiddenPaths)
    }
}
