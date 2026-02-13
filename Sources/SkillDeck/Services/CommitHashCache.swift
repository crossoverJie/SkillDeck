import Foundation

/// CommitHashCache is a private commit hash cache service for SkillDeck
///
/// **Design Decision**: Do not modify the `.skill-lock.json` format to avoid polluting files shared with `npx skills`.
/// SkillDeck stores commit hashes independently in `~/.agents/.skilldeck-cache.json`,
/// so `npx skills add/remove` operations remain unaffected.
///
/// File format:
/// ```json
/// {
///   "skills": {
///     "skill-name": "abc123def456...",
///     "another-skill": "789xyz..."
///   }
/// }
/// ```
///
/// Uses `actor` to ensure thread safety, as multiple operations may read/write the cache file simultaneously.
/// An actor is similar to Go's goroutine + mutex; the compiler automatically ensures only one method executes at a time.
actor CommitHashCache {

    // MARK: - Data Types

    /// JSON structure of the cache file
    /// Codable protocol allows Swift to automatically generate JSON encoding/decoding code (similar to Go's json struct tag)
    private struct CacheFile: Codable {
        /// Stores skill name → commit hash mapping
        var skills: [String: String]
        /// Stores manually linked skill → repository info mapping
        /// optional ensures backward compatibility: old format files lack this field, decoding automatically as nil
        var linkedSkills: [String: LinkedSkillInfo]?
        /// Stores user's scanned repo history
        /// Optional for backward compatibility: old cache files won't have this field, decodes as nil
        var repoHistory: [RepoHistoryEntry]?
    }

    /// History of scanned repos from the Install Sheet
    ///
    /// Records GitHub repos that the user has successfully scanned in the Install Sheet,
    /// so they can quickly select a previously used repo next time without retyping the URL.
    /// Codable protocol auto-generates JSON serialization/deserialization code
    struct RepoHistoryEntry: Codable, Equatable {
        /// Repo source identifier (e.g. "crossoverJie/skills")
        var source: String
        /// Full repo URL (e.g. "https://github.com/crossoverJie/skills.git")
        var sourceUrl: String
        /// Last scanned timestamp (ISO 8601 format)
        var scannedAt: String
    }

    /// Manually linked skill to GitHub repository info
    ///
    /// When a skill has no lockEntry (e.g. directly placed in ~/.claude/skills/),
    /// the user can manually link it to a GitHub repository, stored in this structure.
    /// Fields align with LockEntry to facilitate LockEntry synthesis during refresh.
    /// Codable protocol automatically generates JSON serialization/deserialization code
    struct LinkedSkillInfo: Codable {
        /// Repository source identifier (e.g. "crossoverJie/skills")
        var source: String
        /// Source type (currently fixed to "github")
        var sourceType: String
        /// Full repository URL (e.g. "https://github.com/crossoverJie/skills.git")
        var sourceUrl: String
        /// Relative path of SKILL.md in the repository (e.g. "skills/auto-blog-cover/SKILL.md")
        var skillPath: String
        /// git tree hash of the skill folder (used for update detection)
        var skillFolderHash: String
        /// Link time (ISO 8601 format)
        var linkedAt: String
    }

    // MARK: - Properties

    /// Default path for the cache file: ~/.agents/.skilldeck-cache.json
    /// `static let` is a compile-time constant, similar to Java's static final
    static let defaultPath: URL = {
        let home = NSString(string: "~/.agents/.skilldeck-cache.json").expandingTildeInPath
        return URL(fileURLWithPath: home)
    }()

    /// Current cache file path (can be overridden in tests)
    private let filePath: URL

    /// In-memory cache: skill name → commit hash
    /// Loaded from disk on first access, subsequent operations read/write memory directly, saved to disk on save()
    private var cache: [String: String] = [:]

    /// In-memory cache: skill name → manually linked repository info
    /// Used to store GitHub repository info for manually linked skills without a lockEntry
    private var linkedSkillsCache: [String: LinkedSkillInfo] = [:]

    /// In-memory cache: user's scanned repo history
    /// Deduplicated by source, most recently scanned first, max 20 entries
    private var repoHistoryCache: [RepoHistoryEntry] = []

    /// Whether it has been loaded from disk (to avoid repeated reading)
    private var isLoaded = false

    // MARK: - Initialization

    init(filePath: URL = CommitHashCache.defaultPath) {
        self.filePath = filePath
    }

    // MARK: - Public Methods

    /// Get commit hash for a specific skill
    ///
    /// - Parameter skillName: Unique identifier of the skill (directory name)
    /// - Returns: commit hash, or nil if not cached
    func getHash(for skillName: String) -> String? {
        ensureLoaded()
        return cache[skillName]
    }

    /// Set commit hash for a specific skill (writes to memory only, call save() to persist)
    ///
    /// - Parameters:
    ///   - skillName: Unique identifier of the skill (directory name)
    ///   - hash: Full commit hash (40-character SHA-1)
    func setHash(for skillName: String, hash: String) {
        ensureLoaded()
        cache[skillName] = hash
    }

    // MARK: - Linked Skills Methods (Manually Linked Repo Info)

    /// Get manually linked info for a specific skill
    ///
    /// - Parameter skillName: Unique identifier of the skill (directory name)
    /// - Returns: LinkedSkillInfo, or nil if not linked
    func getLinkedInfo(for skillName: String) -> LinkedSkillInfo? {
        ensureLoaded()
        return linkedSkillsCache[skillName]
    }

    /// Set manually linked info for a specific skill (writes to memory only, call save() to persist)
    ///
    /// - Parameters:
    ///   - skillName: Unique identifier of the skill (directory name)
    ///   - info: Linked repository info
    func setLinkedInfo(for skillName: String, info: LinkedSkillInfo) {
        ensureLoaded()
        linkedSkillsCache[skillName] = info
    }

    /// Remove manually linked info for a specific skill (writes to memory only, call save() to persist)
    ///
    /// When a user formally writes to the lock file via updateSkill,
    /// the linked info in cache can be removed (no longer needed)
    ///
    /// - Parameter skillName: Unique identifier of the skill (directory name)
    func removeLinkedInfo(for skillName: String) {
        ensureLoaded()
        linkedSkillsCache.removeValue(forKey: skillName)
    }

    /// Get all manually linked skill infos
    ///
    /// Used in SkillManager.refresh() to iterate all linked infos,
    /// synthesizing LockEntry for skills without a lockEntry
    func getAllLinkedInfos() -> [String: LinkedSkillInfo] {
        ensureLoaded()
        return linkedSkillsCache
    }

    // MARK: - Repo History Methods

    /// Add or update a repo scan history entry
    ///
    /// Deduplicates by source (e.g. "owner/repo"): if a matching entry exists,
    /// updates its timestamp and moves it to the front. Keeps at most 20 entries (FIFO).
    /// Only writes to memory; call save() to persist to disk.
    ///
    /// - Parameters:
    ///   - source: Repo source identifier (e.g. "crossoverJie/skills")
    ///   - sourceUrl: Full repo URL (e.g. "https://github.com/crossoverJie/skills.git")
    func addRepoHistory(source: String, sourceUrl: String) {
        ensureLoaded()

        // Remove existing entry with the same source (case-insensitive, since GitHub URLs are case-insensitive)
        // removeAll(where:) is like Java Stream's filter + collect — removes matching elements in place
        // caseInsensitiveCompare returns .orderedSame when strings are equal ignoring case
        repoHistoryCache.removeAll { $0.source.caseInsensitiveCompare(source) == .orderedSame }

        // Insert at the front (most recently used first)
        let now = ISO8601DateFormatter().string(from: Date())
        let entry = RepoHistoryEntry(source: source, sourceUrl: sourceUrl, scannedAt: now)
        repoHistoryCache.insert(entry, at: 0)

        // Keep at most 20 entries (prefix takes first N elements, like Python's list[:20])
        if repoHistoryCache.count > 20 {
            repoHistoryCache = Array(repoHistoryCache.prefix(20))
        }
    }

    /// Get all repo scan history entries
    ///
    /// Returns entries sorted by most recent scan time (newest first), max 20 entries
    func getRepoHistory() -> [RepoHistoryEntry] {
        ensureLoaded()
        return repoHistoryCache
    }

    /// Write in-memory cache to disk
    ///
    /// Uses atomic write (.atomic) to ensure file is not corrupted by a crash mid-write:
    /// writes to a temporary file first, then renames to replace the original file upon success.
    /// Similar to the pattern of writing a .tmp file then os.Rename in Go.
    func save() throws {
        // Omit repoHistory from JSON when empty (same pattern as linkedSkillsCache)
        let cacheFile = CacheFile(
            skills: cache,
            linkedSkills: linkedSkillsCache.isEmpty ? nil : linkedSkillsCache,
            repoHistory: repoHistoryCache.isEmpty ? nil : repoHistoryCache
        )
        let encoder = JSONEncoder()
        // prettyPrinted formats the JSON output for human readability and debugging
        // sortedKeys ensures consistent output order, facilitating git diff checks
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(cacheFile)

        // Ensure parent directory exists (~/.agents/)
        let parentDir = filePath.deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        try data.write(to: filePath, options: .atomic)
    }

    // MARK: - Private Methods

    /// Ensure cache is loaded from disk (lazy loading)
    ///
    /// Loads from disk on first call, subsequent calls use in-memory cache directly.
    /// If file doesn't exist or parse fails, use an empty dictionary (no error thrown, degrade gracefully).
    private func ensureLoaded() {
        guard !isLoaded else { return }
        isLoaded = true

        let fm = FileManager.default
        guard fm.fileExists(atPath: filePath.path) else { return }

        do {
            let data = try Data(contentsOf: filePath)
            let cacheFile = try JSONDecoder().decode(CacheFile.self, from: data)
            cache = cacheFile.skills
            // Load linked info (may be nil, old format files lack this field)
            linkedSkillsCache = cacheFile.linkedSkills ?? [:]
            // Load repo scan history (may be nil in old cache files without this field)
            repoHistoryCache = cacheFile.repoHistory ?? []
        } catch {
            // Restart with empty cache if file is corrupted or format incompatible
            // No error thrown because cache loss doesn't affect core functionality, just needs backfill
            cache = [:]
            linkedSkillsCache = [:]
            repoHistoryCache = []        }
    }
}
