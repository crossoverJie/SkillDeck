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
        let metadata: SkillMetadata
        do {
            let decoder = YAMLDecoder()
            metadata = try decoder.decode(SkillMetadata.self, from: yamlString)
        } catch {
            // Fallback: when strict Codable decoding fails (e.g., description contains ": "
            // which Yams misinterprets as a nested mapping key), try raw YAML parsing.
            // Yams.load() returns an untyped dictionary, more lenient with ambiguous values.
            metadata = try parseYAMLFallback(yamlString)
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

    /// Fallback YAML parser: line-by-line extraction for SKILL.md frontmatter
    ///
    /// When YAMLDecoder.decode() fails (e.g., a colon ": " inside a description value
    /// is misinterpreted as a YAML mapping key by the scanner), this method uses
    /// simple line-by-line parsing to extract key-value pairs.
    ///
    /// SKILL.md frontmatter is typically flat (no deep nesting), so line-by-line parsing
    /// is sufficient. The only nested structure is `metadata:` with `author:` and `version:`.
    ///
    /// Why not quote-preprocess + re-parse? Because Yams scanner rejects the raw YAML
    /// before any decoding happens — Yams.load() also fails on ambiguous `: `.
    private static func parseYAMLFallback(_ yamlString: String) throws -> SkillMetadata {
        // Parse line by line, building a flat [String: String] and a nested metadata dict
        var fields: [String: String] = [:]
        var metadataExtra: [String: String] = [:]
        // Track whether we're inside the `metadata:` block (indented sub-keys)
        var inMetadataBlock = false

        for line in yamlString.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") { continue }

            // Check if line is indented (part of a nested block like `metadata:`)
            // In YAML, nested keys are indented with spaces relative to parent
            let isIndented = line.hasPrefix("  ") || line.hasPrefix("\t")

            if isIndented && inMetadataBlock {
                // Parse indented key-value under `metadata:` block
                if let colonIndex = trimmedLine.firstIndex(of: ":") {
                    let key = String(trimmedLine[trimmedLine.startIndex..<colonIndex])
                        .trimmingCharacters(in: .whitespaces)
                    let value = String(trimmedLine[trimmedLine.index(after: colonIndex)...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    metadataExtra[key] = value
                }
                continue
            }

            // Non-indented line: exit metadata block
            inMetadataBlock = false

            // Parse top-level key: value
            // Only split on the FIRST colon (so "desc: foo: bar" → key="desc", value="foo: bar")
            guard let colonIndex = trimmedLine.firstIndex(of: ":") else { continue }
            let key = String(trimmedLine[trimmedLine.startIndex..<colonIndex])
                .trimmingCharacters(in: .whitespaces)
            let value = String(trimmedLine[trimmedLine.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

            if key == "metadata" && value.isEmpty {
                // Start of `metadata:` nested block
                inMetadataBlock = true
                continue
            }

            fields[key] = value
        }

        // Build SkillMetadata from extracted fields
        guard let name = fields["name"], !name.isEmpty else {
            throw ParseError.invalidYAML("Missing required field: name")
        }
        guard let description = fields["description"], !description.isEmpty else {
            throw ParseError.invalidYAML("Missing required field: description")
        }

        // Handle YAML folded/literal scalar indicators (> or |) in description
        // For simple fallback, the description is already extracted as-is
        var metadataObj: SkillMetadata.MetadataExtra?
        if !metadataExtra.isEmpty {
            metadataObj = SkillMetadata.MetadataExtra(
                author: metadataExtra["author"],
                version: metadataExtra["version"]
            )
        }

        return SkillMetadata(
            name: name,
            description: description,
            license: fields["license"],
            metadata: metadataObj,
            allowedTools: fields["allowed-tools"] ?? fields["allowedTools"]
        )
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
