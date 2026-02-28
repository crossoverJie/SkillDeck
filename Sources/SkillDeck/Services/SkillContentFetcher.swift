import Foundation

/// SkillContentFetcher fetches raw SKILL.md content from GitHub for registry skills
///
/// Since skills.sh has no JSON API for individual skill content, we fetch SKILL.md
/// directly from GitHub's raw content CDN (`raw.githubusercontent.com`).
///
/// Repositories use different directory layouts for skills:
/// - **Flat layout**: `{skillId}/SKILL.md` at repo root (e.g., `vercel-labs/agent-skills`)
/// - **Monorepo layout**: `skills/{skillId}/SKILL.md` under a `skills/` subdirectory
///   (e.g., `inference-sh/skills` stores skills at `skills/remotion-render/SKILL.md`)
/// - **Plugin-style layout**: `.claude/skills/{skillId}/SKILL.md` (e.g.,
///   `nextlevelbuilder/ui-ux-pro-max-skill` stores at `.claude/skills/ui-ux-pro-max/SKILL.md`)
/// - **Root layout**: `SKILL.md` at the repository root (single-skill repos)
///
/// Additionally, the directory name on GitHub may differ from the `skillId` returned by
/// the registry API. For example, `remotion-dev/skills` has a skill with
/// `skillId = "remotion-best-practices"` but the directory is just `remotion/`.
/// When direct URL lookup fails, the fetcher falls back to the GitHub Git Tree API
/// to discover the actual path containing the SKILL.md at any nesting depth.
///
/// The fetcher tries all 4 layouts on both `main` and `master` branches (8 attempts total),
/// then falls back to Git Tree API-based discovery if all direct attempts return 404.
///
/// Uses `actor` for thread-safe cache access, consistent with other service actors
/// in the project (SkillRegistryService, LockFileManager, AgentDetector).
/// The `actor` keyword ensures only one task accesses mutable state at a time —
/// similar to Go's goroutine + mutex pattern, but enforced at compile time.
actor SkillContentFetcher {

    // MARK: - Error Types

    /// Errors that can occur when fetching skill content
    ///
    /// Conforms to `LocalizedError` to provide human-readable descriptions via `errorDescription`.
    /// This is the standard Swift pattern for domain-specific errors (similar to Java's custom exceptions).
    enum FetchError: Error, LocalizedError {
        /// Network request failed (timeout, DNS, connection error)
        case networkError(String)
        /// SKILL.md not found at the expected GitHub path (tried both main and master branches)
        case notFound
        /// Server returned an unexpected HTTP status code (not 200 or 404)
        case invalidResponse(Int)
        /// Response body is not valid UTF-8 text
        case invalidEncoding

        /// Human-readable error description (similar to Java's getMessage())
        ///
        /// `errorDescription` is the `LocalizedError` protocol requirement.
        /// Swift 5.9+ allows implicit return for single-expression switch cases.
        var errorDescription: String? {
            switch self {
            case .networkError(let message):
                "Network error: \(message)"
            case .notFound:
                "SKILL.md not found in repository"
            case .invalidResponse(let code):
                "Server returned status \(code)"
            case .invalidEncoding:
                "Response is not valid UTF-8 text"
            }
        }
    }

    // MARK: - Cache

    /// In-memory cache entry storing fetched content and its timestamp
    ///
    /// Tuples in Swift are lightweight unnamed structs — similar to Python's namedtuple.
    /// Keyed by "{source}/{skillId}" string for O(1) lookup.
    private var cache: [String: (content: String, fetchedAt: Date)] = [:]

    /// Cache time-to-live: 10 minutes
    ///
    /// Skill content changes infrequently, so a longer TTL (10 min vs 5 min for leaderboard)
    /// reduces unnecessary network requests when clicking between skills and back.
    private let cacheTTL: TimeInterval = 10 * 60

    // MARK: - Public API

    /// Fetch the raw SKILL.md content for a registry skill from GitHub
    ///
    /// Fetch strategy:
    /// 1. Check in-memory cache (10-minute TTL)
    /// 2. Try direct URLs (8 candidates: 2 branches × 4 layouts) using skillId as directory name
    /// 3. If all 404, fall back to GitHub Git Tree API to discover the actual path
    ///    (handles cases where skillId differs from directory name, e.g., "remotion-best-practices"
    ///    is in directory "remotion", or SKILL.md is deeply nested)
    /// 4. Throw `.notFound` if all attempts fail
    ///
    /// - Parameters:
    ///   - source: Repository in "owner/repo" format (e.g., "vercel-labs/agent-skills")
    ///   - skillId: Skill identifier within the repository (e.g., "vercel-react-best-practices")
    /// - Returns: Raw SKILL.md file content as a string
    /// - Throws: `FetchError` on network failure, missing file, or invalid response
    func fetchContent(source: String, skillId: String) async throws -> String {
        let cacheKey = "\(source)/\(skillId)"

        // 1. Check cache — return cached content if still fresh
        // Date() creates the current timestamp; timeIntervalSince calculates difference in seconds
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.content
        }

        // 2. Try direct candidate URLs: both branch names × both directory layouts.
        // This is the fast path — works when skillId matches the directory name exactly.
        let urls = candidateURLs(source: source, skillId: skillId)
        for url in urls {
            if let content = try await fetchFromURL(url) {
                cache[cacheKey] = (content: content, fetchedAt: Date())
                return content
            }
        }

        // 3. Fallback: use GitHub Git Tree API to discover the actual SKILL.md path.
        // The Tree API returns the entire repo file tree in a single request (recursive=1),
        // so we can find SKILL.md at any depth without multiple API calls.
        // This handles repos where the directory name differs from the skillId,
        // or where SKILL.md is nested in an unexpected location.
        if let content = try await discoverViaTreeAPI(source: source, skillId: skillId) {
            cache[cacheKey] = (content: content, fetchedAt: Date())
            return content
        }

        // 4. All attempts failed — SKILL.md not found
        throw FetchError.notFound
    }

    /// Clear all cached content (for manual refresh scenarios)
    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Internal Helpers

    /// Build the raw GitHub content URL for a SKILL.md file
    ///
    /// GitHub serves raw file content at `raw.githubusercontent.com` without HTML wrapping.
    /// URL pattern: `https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{path}/SKILL.md`
    ///
    /// This is an `internal` (default access) method so tests can verify URL construction
    /// without making actual network requests.
    ///
    /// - Parameters:
    ///   - source: Repository in "owner/repo" format
    ///   - path: Relative path to the skill directory (e.g., "my-skill" or "skills/my-skill")
    ///   - branch: Git branch name ("main" or "master")
    /// - Returns: Fully constructed URL for the raw SKILL.md file
    func buildRawURL(source: String, path: String, branch: String) -> URL {
        // Force-unwrap is safe here because the URL components are controlled by us.
        // `raw.githubusercontent.com` is GitHub's CDN for serving raw file content —
        // it returns plain text without any HTML wrapping or GitHub UI.
        //
        // When `path` is empty (root-level SKILL.md), we must avoid producing a double
        // slash like `/{branch}//SKILL.md`. Instead, emit `/{branch}/SKILL.md`.
        let filePath = path.isEmpty ? "SKILL.md" : "\(path)/SKILL.md"
        return URL(string: "https://raw.githubusercontent.com/\(source)/\(branch)/\(filePath)")!
    }

    /// Generate all candidate URLs to try when fetching a skill's SKILL.md
    ///
    /// Returns URLs ordered by likelihood of success:
    /// 1. `main` branch, flat layout: `{skillId}/SKILL.md` (repo root)
    /// 2. `main` branch, monorepo layout: `skills/{skillId}/SKILL.md` (skills/ subdirectory)
    /// 3. `main` branch, plugin-style: `.claude/skills/{skillId}/SKILL.md`
    /// 4. `main` branch, root layout: `SKILL.md` (repo root, no subdirectory)
    /// 5–8. Same 4 patterns on `master` branch (older repos)
    ///
    /// Many large skill repositories (e.g., `inference-sh/skills`) use a `skills/` subdirectory
    /// to organize skills within a monorepo. Other repos (e.g., `vercel-labs/agent-skills`)
    /// place skill folders directly at the repository root. Some repos (e.g.,
    /// `nextlevelbuilder/ui-ux-pro-max-skill`) use `.claude/skills/` as the skill directory.
    /// Single-skill repos may place SKILL.md directly at the repository root.
    ///
    /// - Parameters:
    ///   - source: Repository in "owner/repo" format
    ///   - skillId: Skill identifier (directory name)
    /// - Returns: Array of candidate URLs to try in order
    func candidateURLs(source: String, skillId: String) -> [URL] {
        // Four possible directory layouts within the repo, ordered by likelihood:
        let paths = [
            skillId,                          // Flat layout: {skillId}/SKILL.md at repo root
            "skills/\(skillId)",              // Monorepo layout: skills/{skillId}/SKILL.md
            ".claude/skills/\(skillId)",      // Plugin-style: .claude/skills/{skillId}/SKILL.md
            "",                               // Root level: SKILL.md at repo root (no subdirectory)
        ]
        // Two possible branch names
        let branches = ["main", "master"]

        // Generate all combinations: branch × path
        // `flatMap` + `map` produces the cartesian product (similar to a nested for-loop)
        // Result: 4 paths × 2 branches = 8 candidate URLs
        return branches.flatMap { branch in
            paths.map { path in
                buildRawURL(source: source, path: path, branch: branch)
            }
        }
    }

    /// Compute the cache key for a source/skillId pair
    ///
    /// Exposed as internal for unit tests to verify cache key format.
    func cacheKey(source: String, skillId: String) -> String {
        "\(source)/\(skillId)"
    }

    // MARK: - Private Networking

    /// Fallback discovery: use GitHub Git Tree API to find the actual SKILL.md path
    ///
    /// When the `skillId` doesn't match the directory name on GitHub (e.g., skillId is
    /// "remotion-best-practices" but the directory is "remotion"), direct URL lookup fails.
    /// This method fetches the entire repository file tree via the Git Tree API in a single
    /// request (recursive mode), then searches for any file named `SKILL.md` at any depth.
    ///
    /// GitHub Git Tree API: `GET /repos/{owner}/{repo}/git/trees/{branch}?recursive=1`
    /// Returns a JSON object with a `tree` array containing all files/directories recursively.
    /// Each entry has `path` (full relative path), `type` ("blob" for files, "tree" for dirs),
    /// and other git metadata.
    ///
    /// Advantages over the Contents API:
    /// - **1 API call per branch** instead of 2+ (one per directory scanned)
    /// - **Unlimited depth** — finds SKILL.md at any nesting level
    /// - **Lower rate limit impact** — 2 total requests (main + master) vs 4+ with Contents API
    ///
    /// Rate limit: 60 requests/hour for unauthenticated requests — sufficient for a desktop app.
    ///
    /// Strategy:
    /// 1. Fetch the full file tree for `main` (then `master` if that fails)
    /// 2. Find all paths ending in `SKILL.md`
    /// 3. For each match, fetch the raw content and verify the `name:` field matches our skillId
    ///
    /// - Parameters:
    ///   - source: Repository in "owner/repo" format
    ///   - skillId: The skill identifier to match against the YAML `name:` field
    /// - Returns: Raw SKILL.md content if found, nil otherwise
    private func discoverViaTreeAPI(source: String, skillId: String) async throws -> String? {
        // Try both "main" and "master" branches
        for branch in ["main", "master"] {
            // Build Git Tree API URL with recursive flag to get the entire tree in one call.
            // Format: `https://api.github.com/repos/{owner}/{repo}/git/trees/{branch}?recursive=1`
            guard let apiURL = URL(
                string: "https://api.github.com/repos/\(source)/git/trees/\(branch)?recursive=1"
            ) else {
                continue
            }

            // Fetch the full file tree from GitHub
            guard let treePaths = await fetchTreeAPIListing(apiURL) else {
                continue
            }

            // Filter for paths ending in "SKILL.md" — these are the candidate files.
            // `hasSuffix` is Swift's endsWith (similar to Java's String.endsWith or Go's strings.HasSuffix).
            let skillMDPaths = treePaths.filter { $0.hasSuffix("SKILL.md") }

            // Try each discovered SKILL.md — fetch content and verify the name matches
            for path in skillMDPaths {
                // Remove the trailing "/SKILL.md" to get the directory path,
                // or use empty string if it's a root-level SKILL.md
                let dirPath: String
                if path == "SKILL.md" {
                    dirPath = ""
                } else {
                    // `dropLast` removes the trailing "/SKILL.md" (10 characters)
                    dirPath = String(path.dropLast("/SKILL.md".count))
                }

                let rawURL = buildRawURL(source: source, path: dirPath, branch: branch)

                guard let content = try await fetchFromURL(rawURL) else {
                    continue
                }

                // Verify this SKILL.md belongs to our skill by checking the `name:` field
                // in the YAML frontmatter. This avoids returning the wrong skill's content
                // in repos with multiple skills.
                if contentMatchesSkillId(content, skillId: skillId) {
                    return content
                }
            }
        }

        return nil
    }

    /// Fetch the full file tree from the GitHub Git Tree API
    ///
    /// Sends a GET request to the Tree API URL and parses the JSON response to extract
    /// all file paths from the `tree` array. Returns nil on any failure (network error,
    /// non-200 status, invalid JSON) — the caller treats this as "tree not available".
    ///
    /// The response JSON structure:
    /// ```json
    /// {
    ///   "sha": "abc123...",
    ///   "tree": [
    ///     {"path": "README.md", "type": "blob", ...},
    ///     {"path": "skills/my-skill/SKILL.md", "type": "blob", ...},
    ///     {"path": "skills", "type": "tree", ...}
    ///   ],
    ///   "truncated": false
    /// }
    /// ```
    ///
    /// We only extract `path` values where `type == "blob"` (files, not directories).
    ///
    /// - Parameter url: The GitHub Git Tree API URL to fetch
    /// - Returns: Array of file paths, or nil on failure
    private func fetchTreeAPIListing(_ url: URL) async -> [String]? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // GitHub API requires a specific Accept header for JSON responses.
        // v3+json is the stable REST API version.
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        // User-Agent is required by GitHub API — requests without it may be rejected
        request.setValue("SkillDeck", forHTTPHeaderField: "User-Agent")

        // Execute request — use `try?` to silently handle network errors
        // (we don't want a network error here to propagate as a FetchError)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        // Parse JSON response and extract the `tree` array.
        // `JSONSerialization` is Foundation's JSON parser (similar to Java's org.json or Go's encoding/json).
        // We cast to [String: Any] (dictionary) since the Tree API returns an object, not an array.
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tree = json["tree"] as? [[String: Any]] else {
            return nil
        }

        // Extract file paths from tree entries (only blobs = files, skip tree = directories).
        // `compactMap` filters out nil values — similar to Java's Stream.filter().map() or
        // Go's slice filtering pattern.
        return tree.compactMap { entry -> String? in
            guard let type = entry["type"] as? String,
                  type == "blob",
                  let path = entry["path"] as? String else {
                return nil
            }
            return path
        }
    }

    /// Check if a SKILL.md content's `name:` field matches the expected skillId
    ///
    /// Searches the YAML frontmatter (between `---` delimiters) for a line matching
    /// `name: {skillId}` or `name: "{skillId}"`. This is a lightweight text check —
    /// we don't need to fully parse the YAML just to verify the name matches.
    ///
    /// - Parameters:
    ///   - content: Raw SKILL.md file content
    ///   - skillId: Expected skill name to match against
    /// - Returns: true if the content's name field matches the skillId
    private func contentMatchesSkillId(_ content: String, skillId: String) -> Bool {
        // Extract the YAML frontmatter section (between first and second "---")
        // to avoid false matches in the markdown body
        let lines = content.components(separatedBy: "\n")

        var inFrontmatter = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                if !inFrontmatter {
                    inFrontmatter = true
                    continue
                } else {
                    // End of frontmatter — stop searching
                    break
                }
            }

            if inFrontmatter {
                // Match "name: skillId" or "name: "skillId"" (with optional quotes)
                // `hasPrefix` is a simple string check — no regex needed for this pattern
                if trimmed.hasPrefix("name:") {
                    let nameValue = trimmed
                        .dropFirst("name:".count)
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    return nameValue == skillId
                }
            }
        }

        return false
    }

    /// Fetch content from a specific URL, returning nil for 404 responses
    ///
    /// Returns `nil` for HTTP 404 (not found) to support the main→master fallback strategy.
    /// Throws `FetchError` for network errors or unexpected HTTP status codes.
    ///
    /// - Parameter url: The URL to fetch content from
    /// - Returns: String content if successful, nil if 404
    /// - Throws: `FetchError` for network or encoding errors
    private func fetchFromURL(_ url: URL) async throws -> String? {
        // Create HTTP request with timeout
        // URLRequest is similar to Java's HttpURLConnection or Go's http.NewRequest
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // Accept plain text — raw.githubusercontent.com returns plain text by default
        request.setValue("text/plain", forHTTPHeaderField: "Accept")

        // Execute async network request
        // URLSession.shared is the singleton HTTP client (similar to Go's http.DefaultClient)
        // `try await` suspends until the response arrives — non-blocking under the hood
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FetchError.networkError(error.localizedDescription)
        }

        // Check HTTP status code
        // `as?` is a conditional type cast (similar to Java's instanceof + cast)
        // `guard let` unwraps the optional and continues; if nil, falls through to the else branch
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.networkError("Invalid response type")
        }

        // 404 = file not found on this branch — return nil to try next branch
        if httpResponse.statusCode == 404 {
            return nil
        }

        // Any other non-200 status is an unexpected error
        guard httpResponse.statusCode == 200 else {
            throw FetchError.invalidResponse(httpResponse.statusCode)
        }

        // Decode response body as UTF-8 string
        guard let content = String(data: data, encoding: .utf8) else {
            throw FetchError.invalidEncoding
        }

        return content
    }
}
