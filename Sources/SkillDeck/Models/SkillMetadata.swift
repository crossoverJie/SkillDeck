import Foundation

/// SkillMetadata corresponds to the fields in YAML frontmatter of SKILL.md
/// Codable protocol allows this struct to be automatically serialized/deserialized (similar to Java's Jackson @JsonProperty)
struct SkillMetadata: Codable, Equatable {
    var name: String
    var description: String
    var license: String?
    var metadata: MetadataExtra?
    var allowedTools: String?

    /// Nested metadata fields (metadata.author, metadata.version in YAML)
    struct MetadataExtra: Codable, Equatable {
        var author: String?
        var version: String?
    }

    // CodingKeys for custom JSON/YAML field name mapping (similar to Go's json tag)
    enum CodingKeys: String, CodingKey {
        case name, description, license, metadata
        case allowedTools = "allowed-tools"
    }

    /// Convenience access to author
    var author: String? { metadata?.author }
    /// Convenience access to version
    var version: String? { metadata?.version }
}
