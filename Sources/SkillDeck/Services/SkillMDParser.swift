import Foundation
import Yams

/// SkillMDParser is responsible for parsing SKILL.md files (YAML frontmatter + Markdown body)
///
/// SKILL.md file format:
/// ```
/// ---
/// name: my-skill
/// description: A skill description
/// license: MIT
/// metadata:
///   author: someone
///   version: "1.0"
/// ---
/// # Markdown content here
/// ```
///
/// Parsing process:
/// 1. Find `---` delimiters to extract frontmatter and body
/// 2. Parse YAML frontmatter into SkillMetadata using Yams library
/// 3. The remaining part serves as the markdown body
enum SkillMDParser {

    /// Parse result: contains metadata and body
    struct ParseResult {
        let metadata: SkillMetadata
        let markdownBody: String
    }

    /// Parse error types
    /// Swift's Error protocol is similar to Java's Exception but more lightweight
    enum ParseError: Error, LocalizedError {
        case fileNotFound(URL)
        case invalidEncoding
        case noFrontmatter
        case invalidYAML(String)

        /// Error description (similar to Java's getMessage())
        var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                "SKILL.md not found at \(url.path)"
            case .invalidEncoding:
                "File is not valid UTF-8"
            case .noFrontmatter:
                "No YAML frontmatter found (missing --- delimiters)"
            case .invalidYAML(let detail):
                "Invalid YAML frontmatter: \(detail)"
            }
        }
    }

    /// Parse SKILL.md from file URL
    /// - Parameter url: Path to SKILL.md file
    /// - Returns: Parse result (metadata + body)
    /// - Throws: ParseError
    ///
    /// `throws` is similar to Java's checked exception or Go's error return
    static func parse(fileURL url: URL) throws -> ParseResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ParseError.fileNotFound(url)
        }

        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw ParseError.invalidEncoding
        }

        return try parse(content: content)
    }

    /// Parse SKILL.md from string content
    /// Exposed for unit testing
    static func parse(content: String) throws -> ParseResult {
        // Extract frontmatter and body
        let (yamlString, body) = try extractFrontmatter(from: content)

        // Parse YAML string into SkillMetadata using Yams library
        // YAMLDecoder is similar to Java's ObjectMapper or Go's json.Unmarshal
        let decoder = YAMLDecoder()
        let metadata: SkillMetadata
        do {
            metadata = try decoder.decode(SkillMetadata.self, from: yamlString)
        } catch {
            throw ParseError.invalidYAML(error.localizedDescription)
        }

        return ParseResult(metadata: metadata, markdownBody: body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Extract YAML frontmatter and markdown body from content
    /// - Returns: (YAML string, Markdown body)
    private static func extractFrontmatter(from content: String) throws -> (String, String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // frontmatter must start with ---
        guard trimmed.hasPrefix("---") else {
            throw ParseError.noFrontmatter
        }

        // Find the position of the second ---
        // Swift string indices are special, not simple Ints (due to variable Unicode character length)
        let afterFirstSeparator = trimmed.index(trimmed.startIndex, offsetBy: 3)
        let rest = trimmed[afterFirstSeparator...]

        guard let endRange = rest.range(of: "\n---") else {
            throw ParseError.noFrontmatter
        }

        let yamlString = String(rest[rest.startIndex..<endRange.lowerBound])
        let bodyStart = rest.index(endRange.upperBound, offsetBy: 0)
        let body = String(rest[bodyStart...])

        return (yamlString, body)
    }

    /// Serialize SkillMetadata back to SKILL.md format string
    /// Used for saving after editing
    static func serialize(metadata: SkillMetadata, markdownBody: String) throws -> String {
        let encoder = YAMLEncoder()
        let yamlString = try encoder.encode(metadata)

        return """
        ---
        \(yamlString.trimmingCharacters(in: .whitespacesAndNewlines))
        ---

        \(markdownBody)
        """
    }
}
