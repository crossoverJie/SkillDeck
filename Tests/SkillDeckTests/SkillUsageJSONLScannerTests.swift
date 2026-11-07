import Darwin
import Foundation
import XCTest

@testable import SkillDeck

/// Covers failure reporting, cache preservation, and bounded-memory line reading.
final class SkillUsageJSONLScannerTests: XCTestCase {
    func testUnreadableLogIsReportedAsFailure() throws {
        try XCTSkipIf(getuid() == 0, "Permission checks do not apply when tests run as root")

        let fixture = try TemporaryFixture()
        defer { fixture.remove() }

        let projects = fixture.root.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let logURL = projects.appendingPathComponent("session.jsonl")
        try "{}\n".write(to: logURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: logURL.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: logURL.path
            )
        }

        let result = makeScanner(directories: [projects], fixture: fixture).scan()

        XCTAssertEqual(result.scannedLogCount, 0)
        XCTAssertEqual(result.failedLogCount, 1)
        XCTAssertTrue(result.records.isEmpty)
    }

    func testUnreadableHistoryDirectoryIsReportedAsFailure() throws {
        try XCTSkipIf(getuid() == 0, "Permission checks do not apply when tests run as root")

        let fixture = try TemporaryFixture()
        defer { fixture.remove() }

        let projects = fixture.root.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: projects.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: projects.path
            )
        }

        let result = makeScanner(directories: [projects], fixture: fixture).scan()

        XCTAssertEqual(result.scannedLogCount, 0)
        XCTAssertEqual(result.failedLogCount, 1)
    }

    /// A failed enumeration must not erase the last known counts for that directory.
    func testEnumerationFailureKeepsCachedCounts() throws {
        try XCTSkipIf(getuid() == 0, "Permission checks do not apply when tests run as root")

        let fixture = try TemporaryFixture()
        defer { fixture.remove() }

        let projects = fixture.root.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let logURL = projects.appendingPathComponent("session.jsonl")
        try "{\"skill\":\"cached-skill\"}\n".write(to: logURL, atomically: true, encoding: .utf8)

        let scanner = SkillUsageJSONLScanner(
            directories: [projects],
            cacheURL: fixture.root.appendingPathComponent("cache.json"),
            fileManager: .default,
            parse: { line in
                line.contains("cached-skill")
                    ? [SkillUsageEvent(skillID: "cached-skill", timestamp: nil)]
                    : []
            }
        )

        let first = scanner.scan()
        XCTAssertEqual(first.scannedLogCount, 1)
        XCTAssertEqual(first.preservedLogCount, 0)
        XCTAssertEqual(first.failedLogCount, 0)
        XCTAssertEqual(first.records["cached-skill"]?.detectedInvocationCount, 1)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: projects.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: projects.path
            )
        }

        let second = scanner.scan()

        XCTAssertEqual(second.failedLogCount, 1)
        XCTAssertEqual(second.scannedLogCount, 1)
        XCTAssertEqual(second.preservedLogCount, 1)
        XCTAssertEqual(second.records["cached-skill"]?.detectedInvocationCount, 1)
    }

    /// An unreadable parent makes the history path impossible to verify, which is a failure
    /// rather than "the Agent is not installed".
    func testInaccessibleHistoryParentIsReportedAsFailure() throws {
        try XCTSkipIf(getuid() == 0, "Permission checks do not apply when tests run as root")

        let fixture = try TemporaryFixture()
        defer { fixture.remove() }

        let agentDirectory = fixture.root.appendingPathComponent("agent", isDirectory: true)
        let historyDirectory = agentDirectory.appendingPathComponent("history", isDirectory: true)
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: agentDirectory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: agentDirectory.path
            )
        }

        let result = makeScanner(directories: [historyDirectory], fixture: fixture).scan()

        XCTAssertEqual(result.scannedLogCount, 0)
        XCTAssertEqual(result.failedLogCount, 1)
    }

    /// A line larger than the 64 KB read chunk must still be parsed exactly once.
    func testReadsLinesAcrossChunkBoundaries() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }

        let projects = fixture.root.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let logURL = projects.appendingPathComponent("session.jsonl")

        let longLine = String(repeating: "x", count: 200_000)
        try (longLine + "\n" + longLine + "\n").write(
            to: logURL,
            atomically: true,
            encoding: .utf8
        )

        let scanner = SkillUsageJSONLScanner(
            directories: [projects],
            cacheURL: fixture.root.appendingPathComponent("cache.json"),
            fileManager: .default,
            parse: { line in
                line.count == 200_000
                    ? [SkillUsageEvent(skillID: "long-line", timestamp: nil)]
                    : []
            }
        )

        let result = scanner.scan()

        XCTAssertEqual(result.scannedLogCount, 1)
        XCTAssertEqual(result.records["long-line"]?.detectedInvocationCount, 2)
    }

    /// Older Codex caches share the same shape, so upgrading must reuse them instead of rescanning.
    func testLegacyCacheVersionIsReusedAndUpgraded() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }

        let projects = fixture.root.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let logURL = projects.appendingPathComponent("session.jsonl")
        try "{\"skill\":\"actual-skill\"}\n".write(to: logURL, atomically: true, encoding: .utf8)

        // Use the enumerator's canonical URL so the cache key matches what the scanner sees.
        let enumeratedLogURL = try XCTUnwrap(
            FileManager.default.enumerator(at: projects, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .first { $0.pathExtension == "jsonl" }
        )
        let values = try enumeratedLogURL.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey]
        )
        let fingerprint = SkillUsageLogFingerprint(
            fileSize: UInt64(try XCTUnwrap(values.fileSize)),
            modificationDate: try XCTUnwrap(values.contentModificationDate)
        )
        let cacheURL = fixture.root.appendingPathComponent("cache.json")
        let legacyCache = SkillUsageLogCache(
            version: 2,
            files: [
                enumeratedLogURL.path: SkillUsageCachedLog(
                    fingerprint: fingerprint,
                    records: [
                        "cached-skill": SkillUsageRecord(
                            detectedInvocationCount: 7,
                            lastDetectedAt: nil
                        ),
                    ]
                ),
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(legacyCache).write(to: cacheURL, options: .atomic)

        let result = makeScanner(directories: [projects], fixture: fixture).scan()

        // The v2 cache was reused instead of rescanning the log, which contains actual-skill.
        XCTAssertEqual(result.scannedLogCount, 1)
        XCTAssertEqual(result.preservedLogCount, 0)
        XCTAssertEqual(result.records["cached-skill"]?.detectedInvocationCount, 7)
        XCTAssertNil(result.records["actual-skill"])

        let upgraded = try JSONDecoder().decode(
            SkillUsageLogCache.self,
            from: Data(contentsOf: cacheURL)
        )
        XCTAssertEqual(upgraded.version, SkillUsageLogCache.currentVersion)
    }

    /// A failed file read keeps the previous cache entry and marks it as preserved.
    func testUnreadableLogKeepsCachedCounts() throws {
        try XCTSkipIf(getuid() == 0, "Permission checks do not apply when tests run as root")

        let fixture = try TemporaryFixture()
        defer { fixture.remove() }

        let projects = fixture.root.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let logURL = projects.appendingPathComponent("session.jsonl")
        try "{\"skill\":\"cached-skill\"}\n".write(to: logURL, atomically: true, encoding: .utf8)

        let scanner = SkillUsageJSONLScanner(
            directories: [projects],
            cacheURL: fixture.root.appendingPathComponent("cache.json"),
            fileManager: .default,
            parse: { line in
                line.contains("cached-skill")
                    ? [SkillUsageEvent(skillID: "cached-skill", timestamp: nil)]
                    : []
            }
        )

        let first = scanner.scan()
        XCTAssertEqual(first.records["cached-skill"]?.detectedInvocationCount, 1)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: logURL.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: logURL.path
            )
        }
        // Invalidate the fingerprint so the scanner must read the file instead of reusing cache.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)],
            ofItemAtPath: logURL.path
        )

        let second = scanner.scan()

        XCTAssertEqual(second.scannedLogCount, 1)
        XCTAssertEqual(second.preservedLogCount, 1)
        XCTAssertEqual(second.failedLogCount, 1)
        XCTAssertEqual(second.records["cached-skill"]?.detectedInvocationCount, 1)
    }

    /// A parser upgrade must rescan only that provider's logs, leaving other caches untouched.
    func testParserVersionChangeDiscardsCachedRecords() throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }

        let projects = fixture.root.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let logURL = projects.appendingPathComponent("session.jsonl")
        try "{\"skill\":\"actual-skill\"}\n".write(to: logURL, atomically: true, encoding: .utf8)

        let cacheURL = fixture.root.appendingPathComponent("cache.json")
        let oldParser = SkillUsageJSONLScanner(
            directories: [projects],
            cacheURL: cacheURL,
            fileManager: .default,
            parse: { _ in [SkillUsageEvent(skillID: "stale-skill", timestamp: nil)] }
        )
        XCTAssertEqual(oldParser.scan().records["stale-skill"]?.detectedInvocationCount, 1)

        let newParser = SkillUsageJSONLScanner(
            directories: [projects],
            cacheURL: cacheURL,
            fileManager: .default,
            parse: { _ in [SkillUsageEvent(skillID: "actual-skill", timestamp: nil)] },
            // Relative to the current default so this test survives future bumps of the
            // shared parser version.
            parserVersion: SkillUsageLogCache.currentParserVersion + 1
        )
        let result = newParser.scan()

        XCTAssertNil(result.records["stale-skill"])
        XCTAssertEqual(result.records["actual-skill"]?.detectedInvocationCount, 1)

        let saved = try JSONDecoder().decode(SkillUsageLogCache.self, from: Data(contentsOf: cacheURL))
        XCTAssertEqual(saved.parserVersion, SkillUsageLogCache.currentParserVersion + 1)
    }

    private func makeScanner(
        directories: [URL],
        fixture: TemporaryFixture
    ) -> SkillUsageJSONLScanner {
        SkillUsageJSONLScanner(
            directories: directories,
            cacheURL: fixture.root.appendingPathComponent("cache.json"),
            fileManager: .default,
            parse: { _ in [] }
        )
    }

    private struct TemporaryFixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("SkillDeckJSONLScannerTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
