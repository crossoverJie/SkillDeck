import Foundation
import Dispatch

/// GitService encapsulates all git CLI operations, core infrastructure for F10 (One-Click Install) and F12 (Update Check)
///
/// Uses `actor` type for thread safety, as git operations involve temporary directories and filesystem read/write,
/// actor ensures only one task executes git commands at a time, avoiding data races.
/// actor is similar to Go's goroutine + channel pattern, but with compiler-enforced safety.
///
/// Design pattern: Reuse the Process API pattern verified in AgentDetector to execute external commands
actor GitService {

    /// Max time to wait for a single git command.
    /// Prevents UI from spinning forever when ssh/git hangs on interactive prompts.
    private static let gitCommandTimeoutSeconds: TimeInterval = 300

    // MARK: - Error Types

    /// Git operation related errors
    /// LocalizedError protocol provides human-readable error descriptions (similar to Java's getMessage())
    enum GitError: Error, LocalizedError {
        /// Git is not installed on the system
        case gitNotInstalled
        /// Git clone failed with error message
        case cloneFailed(String)
        /// Invalid repository URL format
        case invalidRepoURL(String)
        /// Unable to get tree hash (git rev-parse failed)
        case hashResolutionFailed(String)

        var errorDescription: String? {
            switch self {
            case .gitNotInstalled:
                "Git is not installed. Please install git to use this feature."
            case .cloneFailed(let message):
                "Failed to clone repository: \(message)"
            case .invalidRepoURL(let url):
                "Invalid repository URL: \(url)"
            case .hashResolutionFailed(let message):
                "Failed to resolve tree hash: \(message)"
            }
        }
    }

    // MARK: - Data Types

    /// Skill information discovered in remote repository
    /// Identifiable protocol allows SwiftUI's ForEach to iterate directly (requires id property)
    struct DiscoveredSkill: Identifiable {
        /// Unique identifier: skill directory name, e.g. "find-skills"
        let id: String
        /// Relative path within repository, e.g. "skills/find-skills"
        let folderPath: String
        /// Relative path of SKILL.md within repository, e.g. "skills/find-skills/SKILL.md"
        let skillMDPath: String
        /// Parsed SKILL.md metadata
        let metadata: SkillMetadata
        /// Markdown body of SKILL.md
        let markdownBody: String
    }

    // MARK: - Public Methods

    /// Check if git is installed on the system
    /// Detected via `which git` command, exit code 0 means installed
    func checkGitAvailable() async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["git"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Clone repository to temporary directory, supports shallow and full clone
    ///
    /// - Parameters:
    ///   - repoURL: Full repository URL (e.g. "https://github.com/vercel-labs/skills.git")
    ///   - shallow: true uses `--depth 1` shallow clone (only downloads latest commit, faster);
    ///              false performs full clone (includes all git history, for commit hash backfill)
    /// - Returns: Cloned local temporary directory URL
    /// - Throws: GitError.gitNotInstalled or GitError.cloneFailed
    ///
    /// Shallow clone `--depth 1` is similar to go-git's Depth: 1 option in Go.
    /// Full clone requires more time and space, but allows access to git history.
    func cloneRepo(repoURL: String, shallow: Bool, httpAuthorization: String? = nil) async throws -> URL {
        // Create temporary directory: /tmp/SkillDeck-<UUID>/
        // UUID ensures each clone uses a different directory to avoid conflicts
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillDeck-\(UUID().uuidString)")

        // Decide clone depth based on shallow parameter
        var arguments: [String] = []
        if let httpAuthorization {
            arguments += ["-c", "http.extraHeader=\(httpAuthorization)"]
        }
        arguments += ["clone", "--quiet"]
        if shallow {
            arguments += ["--depth", "1"]
        }
        arguments += [repoURL, tempDir.path]

        let output = try await runGitCommand(
            arguments: arguments,
            workingDirectory: nil
        )

        // Verify clone succeeded (check if directory exists)
        guard FileManager.default.fileExists(atPath: tempDir.path) else {
            throw GitError.cloneFailed(output)
        }

        return tempDir
    }

    /// Convenience method for shallow clone (maintains API compatibility)
    ///
    /// Internally calls `cloneRepo(shallow: true)`, equivalent to `git clone --depth 1`
    func shallowClone(repoURL: String, httpAuthorization: String? = nil) async throws -> URL {
        try await cloneRepo(repoURL: repoURL, shallow: true, httpAuthorization: httpAuthorization)
    }

    /// Get commit hash at repository HEAD (full 40-character SHA-1)
    ///
    /// - Parameter repoDir: Local directory of repository
    /// - Returns: Full commit hash string (e.g. "abc123def456...", 40 characters)
    /// - Throws: GitError.hashResolutionFailed
    ///
    /// `git rev-parse HEAD` returns the full SHA-1 hash of the latest commit on current branch.
    /// Note: This is the **commit hash**, not tree hash.
    /// Commit hash identifies a commit, tree hash identifies folder content snapshot.
    /// GitHub compare URL requires commit hash to navigate correctly.
    func getCommitHash(in repoDir: URL) async throws -> String {
        let output = try await runGitCommand(
            arguments: ["rev-parse", "HEAD"],
            workingDirectory: repoDir
        )
        let hash = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty else {
            throw GitError.hashResolutionFailed("Empty commit hash")
        }
        return hash
    }

    /// Search git history for commit that produced specified tree hash (for backfilling old skill's commit hash)
    ///
    /// - Parameters:
    ///   - treeHash: Tree hash to match (from lockEntry.skillFolderHash)
    ///   - folderPath: Relative path of skill in repository (e.g. "skills/find-skills")
    ///   - repoDir: Full clone of repository directory (must contain git history, cannot be shallow clone)
    /// - Returns: Matching commit hash, returns nil if not found
    ///
    /// Implementation principle:
    /// 1. `git log --format=%H -- <folderPath>` gets list of all commits that modified this path
    /// 2. Execute `git rev-parse <commit>:<folderPath>` for each commit to get tree hash under that commit
    /// 3. Compare with target treeHash, return corresponding commit hash if match found
    ///
    /// This method is slower (may require multiple git calls), only called when CommitHashCache has no cache,
    /// result will be cached to `~/.agents/.skilldeck-cache.json`, won't search again subsequently.
    func findCommitForTreeHash(
        treeHash: String, folderPath: String, in repoDir: URL
    ) async throws -> String? {
        // 1. Get list of all commits that modified this path
        // --format=%H only outputs commit hash (one per line), no other info
        let logOutput = try await runGitCommand(
            arguments: ["log", "--format=%H", "--", folderPath],
            workingDirectory: repoDir
        )

        // Split by line to get commit hash list
        let commits = logOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .map(String.init)

        // 2. Check tree hash under this path for each commit
        for commit in commits {
            do {
                let output = try await runGitCommand(
                    arguments: ["rev-parse", "\(commit):\(folderPath)"],
                    workingDirectory: repoDir
                )
                let hash = output.trimmingCharacters(in: .whitespacesAndNewlines)
                // 3. Found matching tree hash, return corresponding commit hash
                if hash == treeHash {
                    return commit
                }
            } catch {
                // Some commits may not contain this path (e.g. before path was renamed), skip
                continue
            }
        }

        // Traversed all commits without finding match
        return nil
    }

    /// Get git tree hash for specified path
    ///
    /// - Parameters:
    ///   - path: Relative path within repository (e.g. "skills/find-skills")
    ///   - repoDir: Local directory of repository
    /// - Returns: Tree hash string (e.g. "abc123def...")
    /// - Throws: GitError.hashResolutionFailed
    ///
    /// `git rev-parse HEAD:<path>` gets tree hash of specified path in HEAD commit,
    /// this hash changes when any file under the path changes, used for update detection.
    /// Similar to tree.Hash in go-git (Go).
    func getTreeHash(for path: String, in repoDir: URL) async throws -> String {
        let output = try await runGitCommand(
            arguments: ["rev-parse", "HEAD:\(path)"],
            workingDirectory: repoDir
        )
        let hash = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty else {
            throw GitError.hashResolutionFailed("Empty hash for path: \(path)")
        }
        return hash
    }

    /// Scan cloned repository directory, discover all skills containing SKILL.md
    ///
    /// - Parameters:
    ///   - repoDir: Local directory of cloned repository
    ///   - includeHiddenPaths: Whether hidden path segments (e.g. `.claude/`) should be scanned.
    ///     Defaults to true for generic scan use-cases. Custom repositories can override this.
    /// - Returns: Array of all discovered skills
    ///
    /// Recursively traverse repository directory tree, find directories containing SKILL.md,
    /// and parse metadata with SkillMDParser. Similar to Go's filepath.Walk.
    func scanSkillsInRepo(repoDir: URL, includeHiddenPaths: Bool = true) -> [DiscoveredSkill] {
        let fm = FileManager.default
        var discovered: [DiscoveredSkill] = []
        let repoDirPath = repoDir.standardizedFileURL.path

        // enumerator recursively traverses directory tree (similar to Python's os.walk or Go's filepath.Walk)
        // includingPropertiesForKeys prefetches file attributes for better performance
        // Don't use .skipsHiddenFiles — some repos store skills under hidden directories
        // like `.claude/skills/`, which would be skipped entirely by that option.
        // Instead, we manually skip `.git` (the only hidden directory we must avoid).
        guard let enumerator = fm.enumerator(
            at: repoDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []  // Don't skip hidden files — .claude/skills/ is hidden but valid
        ) else {
            return []
        }

        // Collect paths of all SKILL.md files, skipping .git directory
        var skillMDURLs: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            // Skip .git directory — it's large and never contains skills.
            // Using lastPathComponent so we catch .git at any nesting level.
            if fileURL.lastPathComponent == ".git" {
                // skipDescendants() tells the enumerator to not recurse into this directory,
                // similar to returning filepath.SkipDir in Go's filepath.Walk.
                enumerator.skipDescendants()
                continue
            }
            if fileURL.lastPathComponent == "SKILL.md" {
                let fullPath = fileURL.standardizedFileURL.path
                if fullPath.hasPrefix(repoDirPath) {
                    var relative = String(fullPath.dropFirst(repoDirPath.count))
                    if relative.hasPrefix("/") {
                        relative = String(relative.dropFirst())
                    }
                    // Custom repos can disable hidden-path scan to avoid ambiguity from
                    // duplicate mirrors under hidden directories.
                    if !includeHiddenPaths && containsHiddenPathSegment(relative) {
                        continue
                    }
                }
                skillMDURLs.append(fileURL)
            }
        }

        // Parse each SKILL.md
        for skillMDURL in skillMDURLs {
            let skillDir = skillMDURL.deletingLastPathComponent()
            let skillName = skillDir.lastPathComponent

            // Calculate path relative to repository root
            // e.g. repoDir = /tmp/xxx/, skillDir = /tmp/xxx/skills/find-skills/
            // → folderPath = "skills/find-skills"
            let repoDirPath = repoDir.standardizedFileURL.path
            let skillDirPath = skillDir.standardizedFileURL.path
            let folderPath: String
            if skillDirPath.hasPrefix(repoDirPath) {
                // dropFirst removes prefix path and leading "/"
                var relative = String(skillDirPath.dropFirst(repoDirPath.count))
                // Remove leading "/" if present
                if relative.hasPrefix("/") {
                    relative = String(relative.dropFirst())
                }
                // Remove trailing "/" if present
                if relative.hasSuffix("/") {
                    relative = String(relative.dropLast())
                }
                folderPath = relative
            } else {
                folderPath = skillName
            }

            let skillMDPath = folderPath.isEmpty
                ? "SKILL.md"
                : "\(folderPath)/SKILL.md"

            // Parse SKILL.md content with SkillMDParser
            do {
                let result = try SkillMDParser.parse(fileURL: skillMDURL)
                discovered.append(DiscoveredSkill(
                    id: skillName,
                    folderPath: folderPath,
                    skillMDPath: skillMDPath,
                    metadata: result.metadata,
                    markdownBody: result.markdownBody
                ))
            } catch {
                // Use directory name as fallback on parse failure, don't block entire scan
                discovered.append(DiscoveredSkill(
                    id: skillName,
                    folderPath: folderPath,
                    skillMDPath: skillMDPath,
                    metadata: SkillMetadata(name: skillName, description: ""),
                    markdownBody: ""
                ))
            }
        }

        // Deduplicate by skill id. If duplicates exist (e.g. hidden mirror + normal path),
        // prefer non-hidden and shallower path.
        var uniqueByID: [String: DiscoveredSkill] = [:]
        for skill in discovered {
            if let existing = uniqueByID[skill.id] {
                if shouldPrefer(skill, over: existing) {
                    uniqueByID[skill.id] = skill
                }
            } else {
                uniqueByID[skill.id] = skill
            }
        }

        // Sort by id with a folderPath tie-breaker for deterministic UI ordering.
        return uniqueByID.values.sorted {
            let lhsID = $0.id.lowercased()
            let rhsID = $1.id.lowercased()
            if lhsID == rhsID {
                return $0.folderPath.lowercased() < $1.folderPath.lowercased()
            }
            return lhsID < rhsID
        }
    }

    private func containsHiddenPathSegment(_ relativePath: String) -> Bool {
        relativePath.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// Pick the better candidate when multiple discovered entries share the same skill id.
    private func shouldPrefer(_ lhs: DiscoveredSkill, over rhs: DiscoveredSkill) -> Bool {
        let lhsHidden = containsHiddenPathComponent(lhs.folderPath)
        let rhsHidden = containsHiddenPathComponent(rhs.folderPath)
        if lhsHidden != rhsHidden {
            return !lhsHidden
        }

        let lhsDepth = lhs.folderPath.split(separator: "/").count
        let rhsDepth = rhs.folderPath.split(separator: "/").count
        if lhsDepth != rhsDepth {
            return lhsDepth < rhsDepth
        }

        return lhs.folderPath.lowercased() < rhs.folderPath.lowercased()
    }

    private func containsHiddenPathComponent(_ folderPath: String) -> Bool {
        folderPath.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// Clean up temporary directory
    /// Called after installation completes or is cancelled, frees disk space
    func cleanupTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Pull latest changes for an already-cloned repository.
    ///
    /// - Parameter repoDir: Local directory of the cloned repository (must contain a `.git` subdirectory)
    /// - Throws: GitError.cloneFailed if `git pull` exits with a non-zero status
    ///
    /// Equivalent to running `git pull` in the repository directory.
    /// SSH authentication is handled transparently by the system's ssh-agent / ~/.ssh/config.
    func pull(repoDir: URL, httpAuthorization: String? = nil) async throws {
        var arguments: [String] = []
        if let httpAuthorization {
            arguments += ["-c", "http.extraHeader=\(httpAuthorization)"]
        }
        arguments += ["pull", "--quiet"]
        _ = try await runGitCommand(
            arguments: arguments,
            workingDirectory: repoDir
        )
    }

    // MARK: - URL Normalization (static methods, no actor isolation needed)

    /// Generate GitHub web URL from git repository URL
    ///
    /// - Parameter sourceUrl: Git repository URL (e.g. "https://github.com/owner/repo.git")
    /// - Returns: GitHub web URL (e.g. "https://github.com/owner/repo"), returns nil for non-GitHub URLs
    ///
    /// `nonisolated` means no actor isolation needed, as it's a pure function without accessing mutable state.
    /// Similar to Java's static method, can be called on any thread without await.
    nonisolated static func githubWebURL(from sourceUrl: String) -> String? {
        // Only handle GitHub URLs
        guard sourceUrl.lowercased().contains("github.com") else { return nil }

        var url = sourceUrl
        // Remove .git suffix
        if url.hasSuffix(".git") {
            url = String(url.dropLast(4))
        }
        // Remove trailing /
        if url.hasSuffix("/") {
            url = String(url.dropLast())
        }
        return url
    }

    /// Normalize repository URL input, supports multiple formats
    ///
    /// Supported input formats:
    /// - `owner/repo` (e.g. "vercel-labs/skills") → auto-completes to GitHub HTTPS URL
    /// - `https://github.com/owner/repo` (full HTTPS URL)
    /// - `https://github.com/owner/repo.git` (with .git suffix)
    /// - `git@github.com:owner/repo.git` (SSH format — passed through unchanged)
    /// - `git@gitlab.com:owner/repo.git` (GitLab SSH format — passed through unchanged)
    ///
    /// - Parameter input: User input repository address
    /// - Returns: Tuple (full repoURL, source identifier for display)
    /// - Throws: GitError.invalidRepoURL
    ///
    /// `nonisolated` keyword means this method doesn't need actor isolation protection,
    /// because it's a pure function, not accessing any mutable state of the actor.
    /// Similar to Java's static method — can be called on any thread without await.
    nonisolated static func normalizeRepoURL(_ input: String) throws -> (repoURL: String, source: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw GitError.invalidRepoURL(input)
        }

        // Case 0: SSH URL format — git@hostname:org/repo.git
        // Passes through unchanged; SSH auth is handled by the system's ssh-agent / ~/.ssh/config.
        // Example: "git@github.com:org/repo.git" → source = "org/repo"
        if trimmed.lowercased().hasPrefix("git@") {
            // Extract org/repo from the path after ":"
            var source = trimmed
            if let colonIdx = source.firstIndex(of: ":") {
                source = String(source[source.index(after: colonIdx)...])
            }
            // Strip .git suffix for the display source
            if source.hasSuffix(".git") {
                source = String(source.dropLast(4))
            }
            // Ensure .git suffix on the clone URL (git requires it for some hosts)
            var repoURL = trimmed
            if !repoURL.hasSuffix(".git") {
                repoURL += ".git"
            }
            return (repoURL: repoURL, source: source)
        }

        // Case 1: Full HTTPS URL (starts with https://)
        if trimmed.lowercased().hasPrefix("https://") {
            // Extract owner/repo from URL as source
            // e.g. "https://github.com/vercel-labs/skills.git" → "vercel-labs/skills"
            var source = trimmed
            // Remove "https://github.com/" prefix
            if let range = source.range(of: "https://github.com/", options: .caseInsensitive) {
                source = String(source[range.upperBound...])
            }
            // Remove .git suffix
            if source.hasSuffix(".git") {
                source = String(source.dropLast(4))
            }
            // Remove trailing /
            if source.hasSuffix("/") {
                source = String(source.dropLast())
            }

            // Ensure repoURL ends with .git
            var repoURL = trimmed
            if !repoURL.hasSuffix(".git") {
                // Remove trailing /
                if repoURL.hasSuffix("/") {
                    repoURL = String(repoURL.dropLast())
                }
                repoURL += ".git"
            }

            return (repoURL: repoURL, source: source)
        }

        // Case 2: owner/repo format (e.g. "vercel-labs/skills")
        // Validate format: must contain exactly one "/"
        let components = trimmed.split(separator: "/")
        guard components.count == 2,
              !components[0].isEmpty,
              !components[1].isEmpty else {
            throw GitError.invalidRepoURL(input)
        }

        // Remove possible .git suffix from repo name
        var repoName = String(components[1])
        if repoName.hasSuffix(".git") {
            repoName = String(repoName.dropLast(4))
        }

        let source = "\(components[0])/\(repoName)"
        let repoURL = "https://github.com/\(source).git"
        return (repoURL: repoURL, source: source)
    }

    // MARK: - Private Methods

    /// Execute git command and return stdout output
    ///
    /// - Parameters:
    ///   - arguments: Git command arguments (excluding "git" itself)
    ///   - workingDirectory: Working directory (nil means use default directory)
    /// - Returns: Command's stdout output
    /// - Throws: GitError
    ///
    /// Uses Process API (similar to Java's ProcessBuilder or Go's exec.Command)
    /// Reuses Process execution pattern verified in AgentDetector
    private func runGitCommand(arguments: [String], workingDirectory: URL?) async throws -> String {
        // First find git's full path (via which git)
        let gitPath = try await findGitPath()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = arguments

        // Force non-interactive behavior so git/ssh fails fast with an error
        // instead of waiting for invisible prompts in a GUI app.
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GCM_INTERACTIVE"] = "Never"
        if env["GIT_SSH_COMMAND"] == nil {
            env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"
        }
        process.environment = env

        // Set working directory (if specified)
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        // Capture output to files instead of pipes to avoid deadlocks when command output is large.
        let fm = FileManager.default
        let captureDir = fm.temporaryDirectory
            .appendingPathComponent("SkillDeck-git-output-\(UUID().uuidString)")
        let stdoutURL = captureDir.appendingPathComponent("stdout.log")
        let stderrURL = captureDir.appendingPathComponent("stderr.log")

        do {
            try fm.createDirectory(at: captureDir, withIntermediateDirectories: true)
            fm.createFile(atPath: stdoutURL.path, contents: nil)
            fm.createFile(atPath: stderrURL.path, contents: nil)
        } catch {
            throw GitError.cloneFailed("Failed to prepare git output capture: \(error.localizedDescription)")
        }

        let stdoutHandle: FileHandle
        let stderrHandle: FileHandle
        do {
            stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
            stderrHandle = try FileHandle(forWritingTo: stderrURL)
        } catch {
            throw GitError.cloneFailed("Failed to open git output capture files: \(error.localizedDescription)")
        }

        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? fm.removeItem(at: captureDir)
        }

        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        do {
            try process.run()
            let exitedInTime = await waitForProcessExit(
                process,
                timeoutSeconds: GitService.gitCommandTimeoutSeconds
            )
            if !exitedInTime {
                process.terminate()
                _ = await waitForProcessExit(process, timeoutSeconds: 5)
                let safeArgs = sanitizeArgumentsForLogging(arguments)
                throw GitError.cloneFailed(
                    "Git command timed out after \(Int(GitService.gitCommandTimeoutSeconds))s: git \(safeArgs.joined(separator: " "))"
                )
            }
        } catch let gitError as GitError {
            throw gitError
        } catch {
            throw GitError.cloneFailed(error.localizedDescription)
        }

        stdoutHandle.synchronizeFile()
        stderrHandle.synchronizeFile()

        let stdoutData = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        // Non-zero exit code means command execution failed
        guard process.terminationStatus == 0 else {
            let errorMessage = stderr.isEmpty ? stdout : stderr
            let trimmed = errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.localizedCaseInsensitiveContains("Host key verification failed") {
                throw GitError.cloneFailed(
                    "\(trimmed)\n\nSSH host key verification failed. Run `ssh -T git@<your-host>` once in Terminal and trust the host key, then retry Sync."
                )
            }
            throw GitError.cloneFailed(trimmed)
        }

        return stdout
    }

    /// Wait for process exit without blocking async contexts.
    /// Returns false when timeout is reached before process exits.
    private func waitForProcessExit(_ process: Process, timeoutSeconds: TimeInterval) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async {
                        process.waitUntilExit()
                        continuation.resume(returning: true)
                    }
                }
            }

            group.addTask {
                let nanos = UInt64(timeoutSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    /// Redact sensitive auth values before composing human-readable logs/errors.
    private func sanitizeArgumentsForLogging(_ arguments: [String]) -> [String] {
        arguments.map { arg in
            if arg.hasPrefix("http.extraHeader=Authorization:") {
                return "http.extraHeader=Authorization: <redacted>"
            }
            return arg
        }
    }

    /// Find full path of git executable
    /// Check common paths first to avoid running which command every time
    private func findGitPath() async throws -> String {
        // Common git installation paths
        let commonPaths = [
            "/usr/bin/git",
            "/usr/local/bin/git",
            "/opt/homebrew/bin/git"
        ]

        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // If common paths not found, find via which command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["git"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw GitError.gitNotInstalled
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !path.isEmpty else {
                throw GitError.gitNotInstalled
            }
            return path
        } catch is GitError {
            throw GitError.gitNotInstalled
        } catch {
            throw GitError.gitNotInstalled
        }
    }
}
