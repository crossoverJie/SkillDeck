import Foundation
import Yams

/// SkillMDParser 负责解析 SKILL.md 文件（YAML frontmatter + Markdown body）
///
/// SKILL.md 文件格式：
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
/// 解析流程：
/// 1. 找到 `---` 分隔符，提取 frontmatter 和 body
/// 2. 用 Yams 库解析 YAML frontmatter 为 SkillMetadata
/// 3. 剩余部分作为 markdown body
enum SkillMDParser {

    /// 解析结果：包含元数据和正文
    struct ParseResult {
        let metadata: SkillMetadata
        let markdownBody: String
    }

    /// 解析错误类型
    /// Swift 的 Error 协议类似 Java 的 Exception，但更轻量
    enum ParseError: Error, LocalizedError {
        case fileNotFound(URL)
        case invalidEncoding
        case noFrontmatter
        case invalidYAML(String)

        /// 错误描述（类似 Java 的 getMessage()）
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

    /// 从文件 URL 解析 SKILL.md
    /// - Parameter url: SKILL.md 文件的路径
    /// - Returns: 解析结果（metadata + body）
    /// - Throws: ParseError
    ///
    /// `throws` 类似 Java 的 checked exception 或 Go 的 error return
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

    /// 从字符串内容解析 SKILL.md
    /// 这个方法也暴露出来方便单元测试
    static func parse(content: String) throws -> ParseResult {
        // 提取 frontmatter 和 body
        let (yamlString, body) = try extractFrontmatter(from: content)

        // 使用 Yams 库将 YAML 字符串解析为 SkillMetadata
        // YAMLDecoder 类似 Java 的 ObjectMapper 或 Go 的 json.Unmarshal
        let decoder = YAMLDecoder()
        let metadata: SkillMetadata
        do {
            metadata = try decoder.decode(SkillMetadata.self, from: yamlString)
        } catch {
            throw ParseError.invalidYAML(error.localizedDescription)
        }

        return ParseResult(metadata: metadata, markdownBody: body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 从内容中提取 YAML frontmatter 和 markdown body
    /// - Returns: (YAML 字符串, Markdown body)
    private static func extractFrontmatter(from content: String) throws -> (String, String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // frontmatter 必须以 --- 开头
        guard trimmed.hasPrefix("---") else {
            throw ParseError.noFrontmatter
        }

        // 找到第二个 --- 的位置
        // Swift 的字符串索引比较特殊，不是简单的 Int（因为 Unicode 字符长度不固定）
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

    /// 将 SkillMetadata 序列化回 SKILL.md 格式的字符串
    /// 用于编辑后保存
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
