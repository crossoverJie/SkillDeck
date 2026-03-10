import Foundation

/// ClawHubSkill models a single skill returned by the ClawHub HTTP API.
///
/// Unlike `RegistrySkill`, which is tightly coupled to skills.sh / GitHub repository semantics,
/// this model captures ClawHub-native concepts such as slug, marketplace stats, owner profile,
/// and the latest published version.
///
/// We intentionally keep this model UI-friendly:
/// - String fields are already normalized for display.
/// - Browser URLs are derived here so Views don't hard-code marketplace URL rules.
/// - Formatted helpers live alongside the raw values, similar to a small view model.
struct ClawHubSkill: Identifiable, Hashable {

    /// Stable marketplace slug used by ClawHub APIs and browser URLs.
    let slug: String

    /// Human-readable skill name.
    /// ClawHub calls this `displayName`; we store it separately from `slug` because the name can
    /// contain spaces and title casing while the slug is filesystem-safe.
    let displayName: String

    /// Short summary shown in list rows and headers.
    let summary: String

    /// Latest published version string if the API exposed one.
    let latestVersion: String?

    /// Download count from marketplace stats.
    let downloads: Int

    /// Star count from marketplace stats.
    let stars: Int

    /// Number of published versions, if the API provided it.
    let versionCount: Int?

    /// ClawHub owner handle (for example `ShawnPana`).
    let ownerHandle: String?

    /// Optional owner display name for richer detail UI.
    let ownerDisplayName: String?

    /// Unix timestamp in milliseconds from the API.
    let updatedAtMilliseconds: Int64?

    /// `Identifiable` conformance lets SwiftUI Lists track each item with stable identity.
    /// The slug is globally unique inside ClawHub, so it is the natural identity key.
    var id: String { slug }

    /// Preferred display name, with slug fallback for incomplete API payloads.
    var name: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? slug : trimmed
    }

    /// User-facing description text with a sensible empty fallback.
    var descriptionText: String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No description provided." : trimmed
    }

    /// Public browser URL for the marketplace detail page.
    ///
    /// This matches the actual ClawHub route pattern discovered from the site metadata:
    /// `https://clawhub.ai/skills/<slug>`.
    var browserURL: URL {
        URL(string: "https://clawhub.ai/skills/\(slug)")!
    }

    /// Formatted download count for compact UI labels.
    var formattedDownloads: String {
        Self.numberFormatter.string(from: NSNumber(value: downloads)) ?? "\(downloads)"
    }

    /// Formatted star count for compact UI labels.
    var formattedStars: String {
        Self.numberFormatter.string(from: NSNumber(value: stars)) ?? "\(stars)"
    }

    /// Human-readable date for the last marketplace update.
    var formattedUpdatedDate: String? {
        guard let updatedAtMilliseconds else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(updatedAtMilliseconds) / 1000)
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}

/// ClawHubSkillDetail contains additional metadata only available from the detail endpoint.
///
/// Keeping this separate avoids forcing every list/search response to fake data it doesn't contain.
struct ClawHubSkillDetail: Hashable {
    let skill: ClawHubSkill
    let latestVersion: String?
    let latestVersionCreatedAt: Int64?
    let latestChangelog: String?
    let license: String?
    let moderationVerdict: String?
    let moderationSummary: String?

    /// Version string to prefer for installation actions.
    ///
    /// We check the detail payload first because it is the most authoritative source.
    var installVersion: String? {
        latestVersion ?? skill.latestVersion
    }

    /// Human-readable publish date for the latest version.
    var formattedLatestVersionDate: String? {
        guard let latestVersionCreatedAt else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(latestVersionCreatedAt) / 1000)
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
