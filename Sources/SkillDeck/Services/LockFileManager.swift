import Foundation

/// LockFileManager is responsible for reading/writing .skill-lock.json file (F07)
///
/// lock file is the central registry for the skills ecosystem, recording all skills installed via package managers.
/// File location: ~/.agents/.skill-lock.json
///
/// Uses actor to ensure thread safety as multiple operations might read/write lock file simultaneously
actor LockFileManager {

    /// Default path for lock file
    static let defaultPath: URL = {
        let home = NSString(string: "~/.agents/.skill-lock.json").expandingTildeInPath
        return URL(fileURLWithPath: home)
    }()

    /// Currently used lock file path (can be overridden in tests)
    let filePath: URL

    /// In-memory cached lock file data
    private var cached: LockFile?

    init(filePath: URL = LockFileManager.defaultPath) {
        self.filePath = filePath
    }

    /// Read and parse lock file
    /// - Returns: LockFile struct
    /// - Throws: File read or JSON parse error
    ///
    /// JSONDecoder is Swift's built-in JSON deserializer (similar to Go's json.Unmarshal)
    func read() throws -> LockFile {
        if let cached {
            return cached
        }

        let data = try Data(contentsOf: filePath)
        let decoder = JSONDecoder()
        let lockFile = try decoder.decode(LockFile.self, from: data)
        cached = lockFile
        return lockFile
    }

    /// Get lock entry for specified skill
    func getEntry(skillName: String) throws -> LockEntry? {
        let lockFile = try read()
        return lockFile.skills[skillName]
    }

    /// Update lock entry for specified skill
    /// Use atomic write to ensure file is not corrupted by mid-operation crashes
    func updateEntry(skillName: String, entry: LockEntry) throws {
        var lockFile = try read()
        lockFile.skills[skillName] = entry
        try write(lockFile)
    }

    /// Remove lock entry for specified skill
    func removeEntry(skillName: String) throws {
        var lockFile = try read()
        lockFile.skills.removeValue(forKey: skillName)
        try write(lockFile)
    }

    /// Write LockFile back to disk
    /// Use atomic write (.atomic option): write to temp file first, then rename, ensuring no partial writes on crash
    /// This is a best practice for file writing, similar to writing .tmp file then os.Rename in Go
    private func write(_ lockFile: LockFile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(lockFile)
        try data.write(to: filePath, options: .atomic)
        cached = lockFile
    }

    /// Invalidate memory cache, forcing next read from disk
    func invalidateCache() {
        cached = nil
    }

    /// Check if lock file exists
    var exists: Bool {
        FileManager.default.fileExists(atPath: filePath.path)
    }

    /// Create empty file if lock file does not exist (F10: used when installing via SkillDeck for the first time)
    ///
    /// Create an empty lock file complying with version 3 format,
    /// Subsequent updateEntry calls can append skill entries directly to it.
    /// If file already exists, do nothing (idempotent operation).
    func createIfNotExists() throws {
        guard !exists else { return }

        // Ensure parent directory (~/.agents/) exists
        let parentDir = filePath.deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: parentDir.path) {
            // withIntermediateDirectories: true is similar to mkdir -p, creating directories recursively
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        // Create empty lock file (version 3 format, compatible with npx skills tool)
        let emptyLockFile = LockFile(
            version: 3,
            skills: [:],
            dismissed: [:],
            lastSelectedAgents: []
        )
        try write(emptyLockFile)
    }
}
