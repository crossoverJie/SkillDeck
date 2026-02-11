import Foundation

/// SkillMetadata 对应 SKILL.md 文件中 YAML frontmatter 的字段
/// Codable 协议让这个 struct 可以自动序列化/反序列化（类似 Java 的 Jackson @JsonProperty）
struct SkillMetadata: Codable, Equatable {
    var name: String
    var description: String
    var license: String?
    var metadata: MetadataExtra?
    var allowedTools: String?

    /// 嵌套的 metadata 字段（YAML 中 metadata.author, metadata.version）
    struct MetadataExtra: Codable, Equatable {
        var author: String?
        var version: String?
    }

    // CodingKeys 用于自定义 JSON/YAML 字段名映射（类似 Go 的 json tag）
    enum CodingKeys: String, CodingKey {
        case name, description, license, metadata
        case allowedTools = "allowed-tools"
    }

    /// 便捷访问 author
    var author: String? { metadata?.author }
    /// 便捷访问 version
    var version: String? { metadata?.version }
}
