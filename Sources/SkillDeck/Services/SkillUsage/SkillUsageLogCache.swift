import Foundation

struct SkillUsageLogFingerprint: Codable, Equatable, Sendable {
    let fileSize: UInt64
    let modificationDate: Date
}

struct SkillUsageCachedLog: Codable, Sendable {
    let fingerprint: SkillUsageLogFingerprint
    let records: [String: SkillUsageRecord]
}

struct SkillUsageLogCache: Codable, Sendable {
    /// Increment when the cache shape or matching semantics change.
    static let currentVersion = 3

    /// Increment when a provider's parsing semantics change. Each provider writes its own cache
    /// file, so bumping this shared default rescans every history; a single provider should
    /// instead pass its own `parserVersion:` to `SkillUsageJSONLScanner` (see
    /// `CodeBuddySkillUsageService` and `PiSkillUsageService`), leaving other caches untouched.
    static let currentParserVersion = 1

    /// Version 2 used the same on-disk shape for Codex. Accepting it avoids forcing a full
    /// rescan of large Codex histories after upgrading; the next save rewrites version 3.
    private static let readableVersions: Set<Int> = [2, currentVersion]

    var version: Int
    var parserVersion: Int
    var files: [String: SkillUsageCachedLog]

    init(
        version: Int = SkillUsageLogCache.currentVersion,
        parserVersion: Int = SkillUsageLogCache.currentParserVersion,
        files: [String: SkillUsageCachedLog] = [:]
    ) {
        self.version = version
        self.parserVersion = parserVersion
        self.files = files
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case parserVersion
        case files
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        // Caches written before parser versioning used the original parsing semantics.
        parserVersion = try container.decodeIfPresent(Int.self, forKey: .parserVersion)
            ?? SkillUsageLogCache.currentParserVersion
        files = try container.decode([String: SkillUsageCachedLog].self, forKey: .files)
    }

    static func load(from url: URL?) -> SkillUsageLogCache {
        guard let url,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(SkillUsageLogCache.self, from: data),
              readableVersions.contains(decoded.version) else {
            return SkillUsageLogCache()
        }
        guard decoded.version != currentVersion else { return decoded }
        return SkillUsageLogCache(
            version: currentVersion,
            parserVersion: decoded.parserVersion,
            files: decoded.files
        )
    }

    func save(to url: URL?, fileManager: FileManager = .default) {
        guard let url else { return }
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(self).write(to: url, options: .atomic)
        } catch {
            // Usage remains available in memory even when cache persistence is not permitted.
        }
    }
}

/// Mutable accumulator shared by all JSONL providers.
struct MutableSkillUsageRecord {
    var detectedInvocationCount = 0
    var lastDetectedAt: Date?
}

enum SkillUsageTimestampParser {
    /// Codex and Qoder timestamps are ISO-8601 and commonly include fractional seconds.
    static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let regular = ISO8601DateFormatter()
        regular.formatOptions = [.withInternetDateTime]
        return regular.date(from: value)
    }

    /// CodeBuddy timestamps are Unix milliseconds.
    static func parseMilliseconds(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue / 1000)
    }
}
