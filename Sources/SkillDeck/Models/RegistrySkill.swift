import Foundation

/// RegistrySkill represents a skill entry from the skills.sh registry
///
/// This model maps to the JSON objects returned by the skills.sh search API
/// (`GET /api/search?q=<query>&limit=<limit>`) and embedded in the leaderboard
/// HTML pages (`/`, `/trending`, `/hot`).
///
/// Codable enables automatic JSON decoding via JSONDecoder (similar to Java's Jackson @JsonProperty).
/// Identifiable provides a unique `id` property so SwiftUI's ForEach/List can iterate directly.
/// Hashable enables use in Set and as Dictionary key.
struct RegistrySkill: Identifiable, Hashable {

    /// Full identifier path (e.g., "vercel-labs/agent-skills/vercel-react-best-practices")
    /// Search API includes this field; leaderboard data may not, so we synthesize it from source + skillId.
    let id: String

    /// Unique skill identifier within the repository (e.g., "vercel-react-best-practices")
    let skillId: String

    /// Display name of the skill
    let name: String

    /// Total installation count (all-time)
    let installs: Int

    /// Repository source in owner/repo format (e.g., "vercel-labs/agent-skills")
    let source: String

    /// Yesterday's install count (only present in trending data, nil for search results)
    let installsYesterday: Int?

    /// Daily change delta (only present in hot data, nil for search/trending results)
    let change: Int?

    /// Convenience: GitHub repository URL derived from source
    /// Used when initiating the install flow (clone this repo to find the skill)
    var repoURL: String {
        "https://github.com/\(source)"
    }

    /// Formatted install count for display (e.g., "135.6K", "1.2M", "500")
    ///
    /// Uses compact number formatting:
    /// - < 1,000: show exact number (e.g., "500")
    /// - 1,000 ~ 999,999: show as K with one decimal (e.g., "135.6K")
    /// - >= 1,000,000: show as M with one decimal (e.g., "1.2M")
    var formattedInstalls: String {
        if installs >= 1_000_000 {
            // Millions: divide by 1M, show one decimal place
            let value = Double(installs) / 1_000_000.0
            return String(format: "%.1fM", value)
        } else if installs >= 1_000 {
            // Thousands: divide by 1K, show one decimal place
            let value = Double(installs) / 1_000.0
            return String(format: "%.1fK", value)
        } else {
            // Small numbers: show exact count
            return "\(installs)"
        }
    }
}

// MARK: - Codable Conformance

/// Manual Codable implementation because the `id` field may be absent in leaderboard data.
/// When `id` is missing (scraped from HTML), we synthesize it as "\(source)/\(skillId)".
///
/// CodingKeys maps JSON field names to Swift property names (similar to Jackson's @JsonProperty in Java).
/// Swift's Codable is the standard serialization protocol — similar to Go's json.Marshal/Unmarshal tags.
extension RegistrySkill: Codable {

    enum CodingKeys: String, CodingKey {
        case id, skillId, name, installs, source, installsYesterday, change
    }

    /// Custom decoder handles missing `id` field in leaderboard data
    ///
    /// `init(from decoder:)` is called by JSONDecoder.decode() automatically.
    /// `decodeIfPresent` returns nil if the key is absent (vs. `decode` which throws).
    /// The `??` operator provides a fallback value — here we construct id from source + skillId.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // skillId and source are always present in both search and leaderboard data
        self.skillId = try container.decode(String.self, forKey: .skillId)
        self.source = try container.decode(String.self, forKey: .source)
        self.name = try container.decode(String.self, forKey: .name)
        self.installs = try container.decode(Int.self, forKey: .installs)
        // id may be absent in leaderboard-scraped data; synthesize from source + skillId
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? "\(source)/\(skillId)"
        // Optional fields: only present in trending/hot data
        self.installsYesterday = try container.decodeIfPresent(Int.self, forKey: .installsYesterday)
        self.change = try container.decodeIfPresent(Int.self, forKey: .change)
    }
}

// MARK: - Search API Response

/// Wrapper for the skills.sh search API JSON response
///
/// Endpoint: GET https://skills.sh/api/search?q={query}&limit={limit}
/// Example response:
/// ```json
/// {
///   "query": "react",
///   "searchType": "fuzzy",
///   "skills": [{ "id": "...", "skillId": "...", "name": "...", "installs": 135601, "source": "..." }],
///   "count": 3,
///   "duration_ms": 25
/// }
/// ```
struct RegistrySearchResponse: Codable {

    /// The search query that was submitted
    let query: String

    /// Type of search performed (e.g., "fuzzy")
    let searchType: String

    /// Array of matching skills
    let skills: [RegistrySkill]

    /// Number of results returned
    let count: Int

    /// Server-side search duration in milliseconds
    let durationMs: Int

    /// CodingKeys maps JSON snake_case to Swift camelCase
    /// `duration_ms` in JSON → `durationMs` in Swift
    enum CodingKeys: String, CodingKey {
        case query, searchType, skills, count
        case durationMs = "duration_ms"
    }
}
