import Foundation

/// SkillRegistryService handles all communication with the skills.sh registry
///
/// Provides two data sources:
/// 1. **Search API**: `GET /api/search?q=<query>&limit=<limit>` — returns clean JSON
/// 2. **Leaderboard scraping**: Fetches HTML from skills.sh pages and extracts embedded
///    Next.js server-rendered skill data (the leaderboard has no public JSON API)
///
/// Uses `actor` for thread safety, consistent with other service actors in the project
/// (GitService, UpdateChecker, AgentDetector). The `actor` keyword in Swift ensures
/// only one task accesses mutable state at a time — similar to Go's goroutine + mutex pattern,
/// but enforced at compile time. All property accesses from outside require `await`.
actor SkillRegistryService {

    // MARK: - Error Types

    /// Errors that can occur during registry operations
    ///
    /// LocalizedError protocol provides human-readable descriptions via `errorDescription`.
    /// This is the standard Swift pattern for domain-specific errors (similar to Java's custom exceptions).
    enum RegistryError: Error, LocalizedError {
        /// Network request failed (timeout, DNS, connection error)
        case networkError(String)
        /// Failed to parse HTML or JSON response
        case parseError(String)
        /// Server returned non-200 HTTP status code
        case invalidResponse(Int)

        /// Human-readable error description (similar to Java's getMessage())
        ///
        /// Swift 5.9+ allows implicit return for single-expression switch cases,
        /// so `return` keyword is omitted — each case is an expression that evaluates to String?.
        var errorDescription: String? {
            switch self {
            case .networkError(let message):
                "Network error: \(message)"
            case .parseError(let message):
                "Parse error: \(message)"
            case .invalidResponse(let code):
                "Server returned status \(code)"
            }
        }
    }

    // MARK: - Leaderboard Category

    /// Leaderboard tab categories matching skills.sh navigation
    ///
    /// CaseIterable allows `ForEach(LeaderboardCategory.allCases)` in SwiftUI.
    /// Identifiable (with `id` = rawValue) enables direct use in SwiftUI lists.
    /// Similar to Java's enum with fields, but Swift enums can also have computed properties.
    enum LeaderboardCategory: String, CaseIterable, Identifiable {
        case allTime = "all-time"
        case trending = "trending"
        case hot = "hot"

        /// Identifiable protocol requirement — uses rawValue as unique ID
        var id: String { rawValue }

        /// Display name shown in UI tabs
        var displayName: String {
            switch self {
            case .allTime: "All Time"
            case .trending: "Trending (24h)"
            case .hot: "Hot"
            }
        }

        /// URL path on skills.sh (appended to base URL)
        /// "/" is the homepage showing all-time leaderboard
        var urlPath: String {
            switch self {
            case .allTime: "/"
            case .trending: "/trending"
            case .hot: "/hot"
            }
        }

        /// SF Symbol icon name for tab display
        /// SF Symbols are Apple's icon library (similar to Material Icons for Android)
        var iconName: String {
            switch self {
            case .allTime: "trophy"
            case .trending: "chart.line.uptrend.xyaxis"
            case .hot: "flame"
            }
        }
    }

    // MARK: - Constants

    /// skills.sh base URL
    private let baseURL = "https://skills.sh"

    /// Search API endpoint
    private let searchAPIPath = "/api/search"

    // MARK: - Caching

    /// Simple in-memory cache for leaderboard data to avoid re-scraping on tab switches
    ///
    /// Dictionary keyed by category, value is a tuple of (skills array, fetch timestamp).
    /// Tuples in Swift are lightweight unnamed structs — similar to Python's namedtuple.
    /// Cache is cleared on manual refresh or after TTL expires.
    private var leaderboardCache: [LeaderboardCategory: (skills: [RegistrySkill], fetchedAt: Date)] = [:]

    /// Cache time-to-live: 5 minutes
    /// Leaderboard data changes slowly, so caching reduces network requests when switching tabs
    private let cacheTTL: TimeInterval = 5 * 60

    // MARK: - Search

    /// Search skills.sh registry using the search API
    ///
    /// Calls `GET https://skills.sh/api/search?q={query}&limit={limit}` and decodes the JSON response.
    ///
    /// - Parameters:
    ///   - query: Search query string (e.g., "react", "typescript")
    ///   - limit: Maximum number of results to return (default 50)
    /// - Returns: Array of matching RegistrySkill objects, sorted by install count (server-side)
    /// - Throws: RegistryError on network or parsing failure
    ///
    /// URLComponents handles URL encoding automatically (spaces → %20, etc.),
    /// similar to Java's URIBuilder or Go's url.Values.
    func search(query: String, limit: Int = 50) async throws -> [RegistrySkill] {
        // Build URL with query parameters using URLComponents (safe URL encoding)
        var components = URLComponents(string: baseURL + searchAPIPath)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components.url else {
            throw RegistryError.networkError("Invalid search URL")
        }

        // Create HTTP request with timeout and Accept header
        // URLRequest is similar to Java's HttpURLConnection or Go's http.NewRequest
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Execute async network request
        // URLSession.shared is the singleton HTTP client (similar to Go's http.DefaultClient)
        // `try await` suspends until the response arrives — similar to Go's blocking I/O but non-blocking under the hood
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw RegistryError.networkError(error.localizedDescription)
        }

        // Check HTTP status code
        // `as?` is a conditional type cast (similar to Java's instanceof + cast)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw RegistryError.invalidResponse(httpResponse.statusCode)
        }

        // Decode JSON response into RegistrySearchResponse struct
        // JSONDecoder is Swift's standard JSON decoder (similar to Java's ObjectMapper or Go's json.Unmarshal)
        do {
            let decoder = JSONDecoder()
            let searchResponse = try decoder.decode(RegistrySearchResponse.self, from: data)
            return searchResponse.skills
        } catch {
            throw RegistryError.parseError("Failed to decode search response: \(error.localizedDescription)")
        }
    }

    // MARK: - Leaderboard

    /// Fetch leaderboard skills for a category by scraping skills.sh HTML
    ///
    /// Since skills.sh doesn't expose a public JSON API for leaderboard data,
    /// we fetch the server-rendered HTML page and extract the embedded skill data
    /// from Next.js `self.__next_f.push()` script tags.
    ///
    /// Flow:
    /// 1. Check in-memory cache (5-minute TTL)
    /// 2. Fetch HTML from skills.sh page (/, /trending, or /hot)
    /// 3. Extract JSON skill data from embedded Next.js server component payload
    /// 4. Decode skill objects using JSONDecoder
    /// 5. Update cache and return
    ///
    /// - Parameter category: Leaderboard category (.allTime, .trending, .hot)
    /// - Returns: Array of RegistrySkill sorted by installs descending
    /// - Throws: RegistryError on network or parsing failure
    func fetchLeaderboard(category: LeaderboardCategory) async throws -> [RegistrySkill] {
        // 1. Check cache — return cached data if still fresh
        // Date() creates the current timestamp; timeIntervalSince calculates the difference in seconds
        if let cached = leaderboardCache[category],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.skills
        }

        // 2. Fetch HTML page
        let urlString = baseURL + category.urlPath
        guard let url = URL(string: urlString) else {
            throw RegistryError.networkError("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // Set User-Agent to appear as a browser — some CDNs/WAFs block requests without a browser-like UA
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw RegistryError.networkError(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw RegistryError.invalidResponse(httpResponse.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw RegistryError.parseError("Unable to decode HTML response as UTF-8")
        }

        // 3. Extract skill data from HTML
        let skills = try parseLeaderboardHTML(html)

        // 4. Update cache
        leaderboardCache[category] = (skills: skills, fetchedAt: Date())

        return skills
    }

    /// Clear all cached leaderboard data (for manual refresh / pull-to-refresh)
    func clearCache() {
        leaderboardCache.removeAll()
    }

    // MARK: - HTML Parsing (Private)

    /// Parse skills.sh HTML to extract embedded skill data from Next.js server component payload
    ///
    /// Next.js App Router with React Server Components embeds data in `self.__next_f.push()` calls
    /// within `<script>` tags. The skill data appears as JSON objects with fields:
    /// `{source, skillId, name, installs}` (and optionally `installsYesterday`, `change`).
    ///
    /// Strategy:
    /// 1. Find all JSON-like objects containing "skillId" and "installs" fields
    /// 2. Extract each object as a substring
    /// 3. Decode using JSONDecoder
    ///
    /// This approach is more resilient than looking for a specific wrapper key like "initialSkills",
    /// because the RSC serialization format may change, but the skill object shape is stable.
    ///
    /// - Parameter html: Raw HTML string from skills.sh page
    /// - Returns: Array of decoded RegistrySkill objects, sorted by installs descending
    /// - Throws: RegistryError.parseError if no skills found
    private func parseLeaderboardHTML(_ html: String) throws -> [RegistrySkill] {
        var skills: [RegistrySkill] = []
        let decoder = JSONDecoder()

        // Strategy: find all JSON objects containing "skillId" key in the HTML
        // We use a simple scanning approach: find each `{"` or `{\"` followed by content containing "skillId"
        //
        // NSRegularExpression is Swift's regex engine (wraps ICU regex, similar to Java's Pattern/Matcher).
        // The pattern matches JSON objects that contain skillId, name, installs, and source fields.
        // [^}]* matches any characters except closing brace — this works because skill objects are flat (no nesting).
        let pattern = #"\{[^}]*"skillId"\s*:\s*"[^"]+"[^}]*"installs"\s*:\s*\d+[^}]*\}"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            throw RegistryError.parseError("Failed to create regex pattern")
        }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length))

        for match in matches {
            let jsonString = nsHTML.substring(with: match.range)

            // The JSON may be inside a JavaScript string literal with escaped quotes (\")
            // Unescape them to get valid JSON: replace \" with "
            // But be careful: the outer HTML already has proper quotes in most cases.
            // We try decoding as-is first, then try unescaping if that fails.
            if let jsonData = jsonString.data(using: .utf8),
               let skill = try? decoder.decode(RegistrySkill.self, from: jsonData) {
                skills.append(skill)
                continue
            }

            // Try unescaping: the content inside __next_f.push() may have escaped quotes
            let unescaped = jsonString
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\/", with: "/")
            if let jsonData = unescaped.data(using: .utf8),
               let skill = try? decoder.decode(RegistrySkill.self, from: jsonData) {
                skills.append(skill)
            }
        }

        // Also try to find skills in escaped JSON strings (inside script tags)
        // Next.js RSC payload often contains JSON as escaped strings within JavaScript:
        // self.__next_f.push([1,"...\"skillId\":\"find-skills\"..."])
        let escapedPattern = #"\\?"skillId\\?"\s*:\\?\s*\\?"([^"\\]+)\\?""#
        if skills.isEmpty, let _ = try? NSRegularExpression(pattern: escapedPattern, options: []) {
            // Extract individual skill objects from escaped JSON strings
            // Find blocks that look like escaped JSON objects with skillId
            let blockPattern = #"\{(?:[^{}]|\\[{}])*\\?"skillId\\?"[^}]*\}"#
            if let blockRegex = try? NSRegularExpression(pattern: blockPattern, options: []) {
                let blockMatches = blockRegex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length))
                for blockMatch in blockMatches {
                    var jsonString = nsHTML.substring(with: blockMatch.range)
                    // Unescape all escaped characters
                    jsonString = jsonString
                        .replacingOccurrences(of: "\\\"", with: "\"")
                        .replacingOccurrences(of: "\\\\/", with: "/")
                        .replacingOccurrences(of: "\\\\", with: "\\")

                    if let jsonData = jsonString.data(using: .utf8),
                       let skill = try? decoder.decode(RegistrySkill.self, from: jsonData) {
                        skills.append(skill)
                    }
                }
            }
        }

        // Deduplicate by id (same skill may appear in multiple script blocks)
        // Dictionary(grouping:) groups by key; we keep the first occurrence.
        // An alternative is using a Set, but RegistrySkill's Hashable is based on all fields.
        var seen = Set<String>()
        skills = skills.filter { skill in
            // insert returns (inserted: Bool, memberAfterInsert: Element)
            // If inserted is true, this is a new id; if false, it's a duplicate
            seen.insert(skill.id).inserted
        }

        guard !skills.isEmpty else {
            throw RegistryError.parseError("No skills found in HTML page")
        }

        // Sort by install count descending (highest installs first)
        // sorted(by:) creates a new sorted array (non-mutating), similar to Java's stream().sorted()
        return skills.sorted { $0.installs > $1.installs }
    }
}
