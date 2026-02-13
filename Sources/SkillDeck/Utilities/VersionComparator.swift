import Foundation

/// VersionComparator is a utility enum for version number comparison (namespace pattern)
///
/// Use enum instead of struct/class as namespace, because enum without cases cannot be instantiated,
/// can only be accessed via static methods, semantically clearer (similar to Java's final class + private constructor).
/// Consistent with the namespace pattern in Constants.swift.
///
/// Supports parsing and comparison of Semantic Versioning:
/// - Format: major.minor.patch (e.g. "1.2.3")
/// - Optional "v" prefix (e.g. "v1.2.3")
/// - Ignore pre-release suffix (e.g. "-beta" in "1.2.3-beta")
enum VersionComparator {

    /// Parse version string into integer array
    ///
    /// Parsing rules:
    /// 1. Remove "v" prefix (e.g. "v1.2.3" -> "1.2.3")
    /// 2. Remove pre-release suffix (e.g. "1.2.3-beta" -> "1.2.3", split by "-" and take first part)
    /// 3. Split by "." and convert to Int array (non-numeric parts ignored)
    ///
    /// - Parameter version: Version string (e.g. "v1.2.3-beta")
    /// - Returns: Integer array (e.g. [1, 2, 3]), parts that cannot be parsed are ignored
    ///
    /// Examples:
    /// - "1.2.3" -> [1, 2, 3]
    /// - "v2.0" -> [2, 0]
    /// - "1.0.0-beta.1" -> [1, 0, 0]
    /// - "dev" -> []
    static func parse(_ version: String) -> [Int] {
        // Swift string operations chain calls (similar to Java's String method chain or Python's str methods)
        var cleaned = version

        // hasPrefix checks string prefix (similar to Java's startsWith)
        // dropFirst() returns Substring removing first character (similar to Python's s[1:])
        // String() converts Substring to String (Swift's Substring and String are different types)
        if cleaned.hasPrefix("v") || cleaned.hasPrefix("V") {
            cleaned = String(cleaned.dropFirst())
        }

        // split(separator:) similar to Java's split() or Go's strings.Split()
        // maxSplits: 1 means only split at the first "-" (keeping subsequent "-" if any)
        // Thus "1.0.0-beta.1" will be split into ["1.0.0", "beta.1"]
        if let dashIndex = cleaned.firstIndex(of: "-") {
            cleaned = String(cleaned[cleaned.startIndex..<dashIndex])
        }

        // compactMap similar to Java Stream's filter+map combination:
        // Execute Int($0) conversion for each element, automatically filtering out failed conversions (returning nil)
        // For example "abc" in "1.2.abc" will be returned as nil by Int(), and thus discarded by compactMap
        return cleaned.split(separator: ".").compactMap { Int($0) }
    }

    /// Compare two version numbers, determine if latest is newer than current
    ///
    /// Compare major -> minor -> patch segment by segment, the first unequal segment determines the result.
    /// If one version has fewer segments than the other, missing segments are treated as 0 (e.g. "1.2" is equivalent to "1.2.0").
    ///
    /// - Parameters:
    ///   - current: Currently installed version (e.g. "1.0.0")
    ///   - latest: Remote latest version (e.g. "1.1.0")
    /// - Returns: true if latest version is newer
    ///
    /// Examples:
    /// - isNewer(current: "1.0.0", latest: "1.0.1") -> true (patch update)
    /// - isNewer(current: "1.0.0", latest: "1.0.0") -> false (same version)
    /// - isNewer(current: "2.0.0", latest: "1.9.9") -> false (current is newer)
    static func isNewer(current: String, latest: String) -> Bool {
        let currentParts = parse(current)
        let latestParts = parse(latest)

        // Use maximum segment count of two versions as comparison length
        // max() is Swift global function (similar to Math.max)
        let count = max(currentParts.count, latestParts.count)

        for i in 0..<count {
            // If a version has insufficient segments, pad with 0
            // e.g. 3rd segment of "1.2" is treated as 0, equivalent to "1.2.0"
            // Ternary operator consistent with Java/Go/Python syntax
            let c = i < currentParts.count ? currentParts[i] : 0
            let l = i < latestParts.count ? latestParts[i] : 0

            if l > c { return true }   // latest has larger segment, indicating update
            if l < c { return false }  // latest has smaller segment, indicating old version
            // l == c continue to compare next segment
        }

        // All segments equal, versions are same, not an update
        return false
    }
}
