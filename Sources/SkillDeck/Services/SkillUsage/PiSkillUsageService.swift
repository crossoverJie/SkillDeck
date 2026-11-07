import Foundation

/// Recovers skill activations from Pi's per-project JSONL session history.
///
/// Pi writes no dedicated activation event. Two shapes count as one invocation:
///
/// 1. **Injected skill body (primary path).** When a skill is actually activated (slash
///    command / `@`-style skill reference), Pi expands `SKILL.md` into a **user** message whose
///    text block starts with `<skill name="…" location="…/SKILL.md">` followed by the file body
///    and a closing `</skill>`. There is no tool call in that message, so an earlier
///    read-tool-only parser never saw real activations.
/// 2. **Explicit `read` tool call.** When the model loads a `SKILL.md` itself it emits an
///    assistant `toolCall` block named `read` whose `path` argument is a trusted skill file.
///
/// Thinking text, bash churn over repository copies, and the `<available_skills>` prompt
/// section all mention `SKILL.md` without invoking anything; requiring a leading `<skill …>`
/// prefix on user text (Pi always injects it at position 0) or a `read` toolCall in trusted
/// directories excludes them.
actor PiSkillUsageService: SkillUsageProvider {
    nonisolated var agentType: AgentType { .pi }

    /// Parser version local to Pi's cache file (`…-pi.json`).
    ///
    /// The first shipped parser only understood `read` toolCalls and therefore recorded nothing
    /// for real Pi activations. Version 2 also understands injected `<skill …>` user messages,
    /// so caches written by version 1 must be rebuilt. Keeping the bump here rather than in
    /// `SkillUsageLogCache.currentParserVersion` avoids rescanning the other Agents' histories.
    private static let parserVersion = 2

    private let scanner: SkillUsageJSONLScanner

    /// Production initializer based on the current macOS user's home directory.
    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        let piDirectory = homeDirectory
            .appendingPathComponent(".pi", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
        let agentsDirectory = homeDirectory.appendingPathComponent(".agents", isDirectory: true)

        self.scanner = SkillUsageJSONLScanner(
            directories: [piDirectory.appendingPathComponent("sessions", isDirectory: true)],
            cacheURL: agentsDirectory
                .appendingPathComponent(".skilldeck-usage-cache-pi.json"),
            fileManager: fileManager,
            parse: Self.makeParse(homeDirectory: homeDirectory.standardizedFileURL),
            parserVersion: Self.parserVersion
        )
    }

    /// Test initializer that avoids depending on the developer machine's real Pi history.
    init(
        historyDirectories: [URL],
        homeDirectory: URL,
        cacheURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.scanner = SkillUsageJSONLScanner(
            directories: historyDirectories,
            cacheURL: cacheURL,
            fileManager: fileManager,
            parse: Self.makeParse(homeDirectory: homeDirectory.standardizedFileURL),
            parserVersion: Self.parserVersion
        )
    }

    func scan() -> SkillUsageScanResult {
        scanner.scan()
    }

    private static func makeParse(homeDirectory: URL) -> @Sendable (String) -> [SkillUsageEvent] {
        return { line in
            // Most history lines never touch a skill. This cheap filter avoids JSON parsing for them.
            guard line.contains("SKILL.md") else { return [] }

            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "message",
                  let message = object["message"] as? [String: Any],
                  let blocks = message["content"] as? [[String: Any]] else {
                return []
            }

            let timestamp = (object["timestamp"] as? String)
                .flatMap(SkillUsageTimestampParser.parseISO8601)

            // `role` decides which block shape is meaningful: injected skill bodies arrive as
            // user text, while a model-initiated load is an assistant toolCall. Checking it
            // keeps a user quoting `<skill …>` mid-conversation from being misread.
            let role = message["role"] as? String

            var skillIDs: Set<String> = []
            for block in blocks {
                let skillID: String?
                switch role {
                case "user":
                    skillID = injectedSkillID(in: block, homeDirectory: homeDirectory)
                case "assistant":
                    skillID = readToolCallSkillID(in: block, homeDirectory: homeDirectory)
                default:
                    skillID = nil
                }
                if let skillID {
                    skillIDs.insert(skillID)
                }
            }
            return skillIDs.map { SkillUsageEvent(skillID: $0, timestamp: timestamp) }
        }
    }

    /// Skill directory name for a model-initiated load: an assistant `read` toolCall whose
    /// `path` argument points at a trusted `SKILL.md`.
    private static func readToolCallSkillID(
        in block: [String: Any],
        homeDirectory: URL
    ) -> String? {
        guard block["type"] as? String == "toolCall",
              block["name"] as? String == "read",
              let arguments = block["arguments"] as? [String: Any],
              let path = arguments["path"] as? String else {
            return nil
        }
        return trustedSkillID(atPath: path, homeDirectory: homeDirectory)
    }

    /// Skill directory name for a Pi-injected skill body.
    ///
    /// Pi prepends the activation marker to the message text, so requiring the block to start
    /// with `<skill ` (after leading whitespace) filters out prose, prompt listings, and tool
    /// output that merely mention a skill path.
    private static func injectedSkillID(
        in block: [String: Any],
        homeDirectory: URL
    ) -> String? {
        guard block["type"] as? String == "text",
              let text = block["text"] as? String else {
            return nil
        }

        // `Substring` avoids copying the (potentially 10 KB+) injected skill body.
        let trimmed = text.drop(while: { $0 == " " || $0 == "\n" || $0 == "\t" })
        guard trimmed.hasPrefix("<skill "),
              let locationStart = trimmed.range(of: "location=\"")?.upperBound else {
            return nil
        }
        let remainder = trimmed[locationStart...]
        guard let locationEnd = remainder.firstIndex(of: "\"") else { return nil }
        return trustedSkillID(
            atPath: String(remainder[..<locationEnd]),
            homeDirectory: homeDirectory
        )
    }

    /// Skill directory name when the path points into SkillDeck's canonical store or Pi's own
    /// skills directory. Paths elsewhere (for example a repository copy being edited) are ignored
    /// so development work never counts as usage.
    private static func trustedSkillID(atPath path: String, homeDirectory: URL) -> String? {
        let expandedPath: String
        if path.hasPrefix("~/") {
            expandedPath = homeDirectory
                .appendingPathComponent(String(path.dropFirst(2)))
                .path
        } else {
            expandedPath = path
        }

        guard expandedPath.hasPrefix("/") else { return nil }
        let pathComponents = URL(fileURLWithPath: expandedPath).standardizedFileURL.pathComponents
        let homeComponents = homeDirectory.pathComponents
        guard pathComponents.starts(with: homeComponents),
              pathComponents.last == "SKILL.md" else {
            return nil
        }

        let relative = Array(pathComponents.dropFirst(homeComponents.count))
        if relative.count == 4, relative[0] == ".agents", relative[1] == "skills" {
            return relative[2].isEmpty ? nil : relative[2]
        }
        if relative.count == 5, relative[0] == ".pi", relative[1] == "agent", relative[2] == "skills" {
            return relative[3].isEmpty ? nil : relative[3]
        }
        return nil
    }
}
