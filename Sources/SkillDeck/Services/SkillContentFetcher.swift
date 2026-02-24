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
///
/// The fetcher tries both layouts on both `main` and `master` branches (4 attempts total).
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
    /// Fetch strategy (tries up to 4 URLs, stops on first success):
    /// 1. Check in-memory cache (10-minute TTL)
    /// 2. Try `main` branch, flat layout: `{skillId}/SKILL.md`
    /// 3. Try `main` branch, monorepo layout: `skills/{skillId}/SKILL.md`
    /// 4. Try `master` branch, flat layout: `{skillId}/SKILL.md`
    /// 5. Try `master` branch, monorepo layout: `skills/{skillId}/SKILL.md`
    /// 6. Throw `.notFound` if all attempts return 404
    ///
    /// Many skill repositories use a `skills/` subdirectory (monorepo layout) rather than
    /// placing skill folders at the repo root. For example, `inference-sh/skills` stores
    /// skills at `skills/remotion-render/SKILL.md`, not `remotion-render/SKILL.md`.
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

        // 2. Try all candidate URLs: both branch names × both directory layouts.
        // `candidateURLs` returns URLs ordered by likelihood:
        // main/flat → main/skills/ → master/flat → master/skills/
        let urls = candidateURLs(source: source, skillId: skillId)
        for url in urls {
            if let content = try await fetchFromURL(url) {
                cache[cacheKey] = (content: content, fetchedAt: Date())
                return content
            }
        }

        // 3. All candidate URLs returned 404 — SKILL.md not found
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
        URL(string: "https://raw.githubusercontent.com/\(source)/\(branch)/\(path)/SKILL.md")!
    }

    /// Generate all candidate URLs to try when fetching a skill's SKILL.md
    ///
    /// Returns URLs ordered by likelihood of success:
    /// 1. `main` branch, flat layout: `{skillId}/SKILL.md` (repo root)
    /// 2. `main` branch, monorepo layout: `skills/{skillId}/SKILL.md` (skills/ subdirectory)
    /// 3. `master` branch, flat layout (older repos)
    /// 4. `master` branch, monorepo layout (older repos)
    ///
    /// Many large skill repositories (e.g., `inference-sh/skills`) use a `skills/` subdirectory
    /// to organize skills within a monorepo. Other repos (e.g., `vercel-labs/agent-skills`)
    /// place skill folders directly at the repository root.
    ///
    /// - Parameters:
    ///   - source: Repository in "owner/repo" format
    ///   - skillId: Skill identifier (directory name)
    /// - Returns: Array of candidate URLs to try in order
    func candidateURLs(source: String, skillId: String) -> [URL] {
        // Two possible directory layouts within the repo
        let paths = [
            skillId,              // Flat layout: {skillId}/SKILL.md at repo root
            "skills/\(skillId)",  // Monorepo layout: skills/{skillId}/SKILL.md
        ]
        // Two possible branch names
        let branches = ["main", "master"]

        // Generate all combinations: branch × path
        // `flatMap` + `map` produces the cartesian product (similar to a nested for-loop)
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
