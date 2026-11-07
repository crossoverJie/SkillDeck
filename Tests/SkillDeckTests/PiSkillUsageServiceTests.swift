import Foundation
import XCTest

@testable import SkillDeck

final class PiSkillUsageServiceTests: XCTestCase {
    func testScanCountsReadToolCallsInTrustedDirectories() async throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }

        let home = fixture.root.appendingPathComponent("home", isDirectory: true)
        let sessions = home
            .appendingPathComponent(".pi", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        let project = sessions.appendingPathComponent("--repo--", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let lines = [
            // Canonical store and Pi's own directory: both count as activations.
            try makeReadCall(
                timestamp: "2026-11-01T05:06:18.458Z",
                path: home.appendingPathComponent(".agents/skills/skilldeck/SKILL.md").path
            ),
            try makeReadCall(
                timestamp: "2026-11-01T05:07:18.458Z",
                path: "~/.pi/agent/skills/gzh-design/SKILL.md"
            ),
            try makeReadCall(
                timestamp: "2026-11-01T05:08:18.458Z",
                path: home.appendingPathComponent(".agents/skills/skilldeck/SKILL.md").path
            ),
            // Development work outside the skill stores must not count as usage.
            try makeReadCall(
                timestamp: "2026-11-01T05:09:18.458Z",
                path: "/Users/test/dev/repo/skills/starrocks-upgrade/SKILL.md"
            ),
            // Bash churn and thinking text mention SKILL.md without activating a skill.
            try makeToolCall(
                timestamp: "2026-11-01T05:10:18.458Z",
                name: "bash",
                arguments: ["command": "diff ~/.agents/skills/skilldeck/SKILL.md /tmp/copy.md"]
            ),
            try makeThinking(
                timestamp: "2026-11-01T05:11:18.458Z",
                text: "I should read the SKILL.md for skilldeck later."
            ),
            // The available-skills prompt section lists paths without invoking them.
            try makePromptSection(timestamp: "2026-11-01T05:12:18.458Z"),
            // Two reads of the same skill inside one message count once.
            try makeMessage(timestamp: "2026-11-01T05:13:18.458Z", blocks: [
                readBlock(home.appendingPathComponent(".agents/skills/dup/SKILL.md").path),
                readBlock(home.appendingPathComponent(".agents/skills/dup/SKILL.md").path),
            ]),
            "{ malformed json",
        ]
        try writeJSONL(lines, to: project.appendingPathComponent("session.jsonl"))

        let result = await PiSkillUsageService(
            historyDirectories: [sessions],
            homeDirectory: home,
            cacheURL: fixture.root.appendingPathComponent("cache.json")
        ).scan()

        XCTAssertEqual(result.scannedLogCount, 1)
        XCTAssertEqual(result.failedLogCount, 0)
        XCTAssertEqual(result.records["skilldeck"]?.detectedInvocationCount, 2)
        XCTAssertEqual(result.records["gzh-design"]?.detectedInvocationCount, 1)
        XCTAssertEqual(result.records["starrocks-upgrade"]?.detectedInvocationCount, nil)
        XCTAssertEqual(result.records["dup"]?.detectedInvocationCount, 1)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(
            result.records["skilldeck"]?.lastDetectedAt,
            formatter.date(from: "2026-11-01T05:08:18.458Z")
        )
    }

    func testScanCountsInjectedSkillBodiesFromUserMessages() async throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }

        let home = fixture.root.appendingPathComponent("home", isDirectory: true)
        let sessions = home
            .appendingPathComponent(".pi", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        let project = sessions.appendingPathComponent("--repo--", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let lines = [
            // Real Pi activation: the whole SKILL.md is injected into a user message that
            // starts with `<skill name="…" location="…/SKILL.md">`. No toolCall is emitted.
            try makeInjectedSkill(
                timestamp: "2026-11-07T14:21:01.757Z",
                name: "writing-plans",
                location: home
                    .appendingPathComponent(".agents/skills/writing-plans/SKILL.md").path
            ),
            // Pi's own skills directory is trusted too.
            try makeInjectedSkill(
                timestamp: "2026-11-07T14:22:01.757Z",
                name: "gzh-design",
                location: home
                    .appendingPathComponent(".pi/agent/skills/gzh-design/SKILL.md").path
            ),
            // A quoted marker inside normal prose is not an activation.
            try makeUserText(
                timestamp: "2026-11-07T14:23:01.757Z",
                text: "see <skill name=\"fake\" location=\"\(home.path)/.agents/skills/fake/SKILL.md\">"
            ),
            // An injected body from outside the skill stores (repo copy) must not count.
            try makeInjectedSkill(
                timestamp: "2026-11-07T14:24:01.757Z",
                name: "repo-copy",
                location: "/Users/test/dev/repo/skills/repo-copy/SKILL.md"
            ),
        ]
        try writeJSONL(lines, to: project.appendingPathComponent("session.jsonl"))

        let result = await PiSkillUsageService(
            historyDirectories: [sessions],
            homeDirectory: home,
            cacheURL: fixture.root.appendingPathComponent("cache.json")
        ).scan()

        XCTAssertEqual(result.records["writing-plans"]?.detectedInvocationCount, 1)
        XCTAssertEqual(result.records["gzh-design"]?.detectedInvocationCount, 1)
        XCTAssertEqual(result.records["fake"]?.detectedInvocationCount, nil)
        XCTAssertEqual(result.records["repo-copy"]?.detectedInvocationCount, nil)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(
            result.records["writing-plans"]?.lastDetectedAt,
            formatter.date(from: "2026-11-07T14:21:01.757Z")
        )
    }

    /// The Pi parser bump must invalidate Pi's own cache without touching the shared default.
    func testPiParserVersionDiscardsStaleCacheEntries() async throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }

        let home = fixture.root.appendingPathComponent("home", isDirectory: true)
        let sessions = home
            .appendingPathComponent(".pi", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        let project = sessions.appendingPathComponent("--repo--", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let logURL = project.appendingPathComponent("session.jsonl")
        try writeJSONL([
            try makeInjectedSkill(
                timestamp: "2026-11-07T14:21:01.757Z",
                name: "writing-plans",
                location: home
                    .appendingPathComponent(".agents/skills/writing-plans/SKILL.md").path
            ),
        ], to: logURL)

        // A cache written by the read-tool-only parser: same file fingerprint, wrong records.
        let cacheURL = fixture.root.appendingPathComponent("cache.json")
        let values = try logURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        var stale = SkillUsageLogCache(parserVersion: 1)
        stale.files[logURL.path] = SkillUsageCachedLog(
            fingerprint: SkillUsageLogFingerprint(
                fileSize: UInt64(try XCTUnwrap(values.fileSize)),
                modificationDate: try XCTUnwrap(values.contentModificationDate)
            ),
            records: [
                "stale-skill": SkillUsageRecord(
                    detectedInvocationCount: 7,
                    lastDetectedAt: nil
                ),
            ]
        )
        stale.save(to: cacheURL)

        let result = await PiSkillUsageService(
            historyDirectories: [sessions],
            homeDirectory: home,
            cacheURL: cacheURL
        ).scan()

        XCTAssertEqual(result.records["stale-skill"]?.detectedInvocationCount, nil)
        XCTAssertEqual(result.records["writing-plans"]?.detectedInvocationCount, 1)

        // Other providers keep using the shared default, so their caches stay reusable.
        XCTAssertEqual(SkillUsageLogCache.currentParserVersion, 1)
    }

    func testScanReturnsNoCoverageWhenHistoryIsMissing() async throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }

        let missing = fixture.root.appendingPathComponent("sessions", isDirectory: true)
        let result = await PiSkillUsageService(
            historyDirectories: [missing],
            homeDirectory: fixture.root
        ).scan()

        XCTAssertEqual(result.scannedLogCount, 0)
        XCTAssertEqual(result.failedLogCount, 0)
        XCTAssertTrue(result.records.isEmpty)
    }

    // MARK: - Fixtures

    private func readBlock(_ path: String) -> [String: Any] {
        [
            "type": "toolCall",
            "id": "call_\(UUID().uuidString)",
            "name": "read",
            "arguments": ["path": path],
        ]
    }

    private func makeReadCall(timestamp: String, path: String) throws -> String {
        try makeMessage(timestamp: timestamp, blocks: [readBlock(path)])
    }

    private func makeToolCall(timestamp: String, name: String, arguments: [String: Any]) throws -> String {
        try makeMessage(timestamp: timestamp, blocks: [
            ["type": "toolCall", "id": "call_1", "name": name, "arguments": arguments],
        ])
    }

    private func makeMessage(timestamp: String, blocks: [[String: Any]]) throws -> String {
        try jsonLine([
            "type": "message",
            "timestamp": timestamp,
            "message": [
                "role": "assistant",
                "content": blocks,
            ],
        ])
    }

    private func makeThinking(timestamp: String, text: String) throws -> String {
        try jsonLine([
            "type": "message",
            "timestamp": timestamp,
            "message": [
                "role": "assistant",
                "content": [["type": "thinking", "text": text]],
            ],
        ])
    }

    /// Mirrors Pi's skill expansion: a user message whose first text block starts with the
    /// `<skill name location>` marker and continues with the SKILL.md body.
    private func makeInjectedSkill(
        timestamp: String,
        name: String,
        location: String
    ) throws -> String {
        try makeUserText(
            timestamp: timestamp,
            text: "<skill name=\"\(name)\" location=\"\(location)\">\nReferences are relative to .\n\n# \(name)\n</skill>\n\nuse it"
        )
    }

    private func makeUserText(timestamp: String, text: String) throws -> String {
        try jsonLine([
            "type": "message",
            "timestamp": timestamp,
            "message": [
                "role": "user",
                "content": [["type": "text", "text": text]],
            ],
        ])
    }

    private func makePromptSection(timestamp: String) throws -> String {
        try jsonLine([
            "type": "message",
            "timestamp": timestamp,
            "message": [
                "role": "user",
                "content": [["type": "text", "text": "hello"]],
                "sections": ["skills": "<available_skills> SKILL.md listing </available_skills>"],
            ],
        ])
    }

    private func jsonLine(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func writeJSONL(_ lines: [String], to url: URL) throws {
        let contents = lines.joined(separator: "\n") + "\n"
        try XCTUnwrap(contents.data(using: .utf8)).write(to: url, options: .atomic)
    }

    private struct TemporaryFixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("SkillDeckPiTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
