import Darwin
import Foundation
import SQLite3
import XCTest

@testable import SkillDeck

final class OpenCodeSkillUsageServiceTests: XCTestCase {
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    func testScanCountsCompletedSkillPartsOnly() async throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }

        let databaseURL = fixture.root.appendingPathComponent("opencode.db")
        try makeDatabase(at: databaseURL, rows: [
            Row(id: "p1", tool: "skill", skill: "web-access", status: "completed", timestamp: 1_790_000_000_000),
            Row(id: "p2", tool: "skill", skill: "web-access", status: "error", timestamp: 1_790_000_100_000),
            Row(id: "p3", tool: "skill", skill: "gzh-design", status: "completed", timestamp: 1_790_000_200_000),
            Row(id: "p4", tool: "bash", skill: "ignored", status: "completed", timestamp: 1_790_000_300_000),
        ])

        let service = OpenCodeSkillUsageService(databaseURL: databaseURL)
        let result = await service.scan()

        // Locks in the "prefer read-only" contract: a plain (non-WAL) database must never be
        // opened read-write, because that handle can create sidecar files.
        let openMode = await service.lastOpenMode
        XCTAssertEqual(openMode, .readOnly)

        XCTAssertEqual(result.scannedLogCount, 1)
        XCTAssertEqual(result.failedLogCount, 0)
        XCTAssertEqual(result.records["web-access"]?.detectedInvocationCount, 1)
        XCTAssertEqual(result.records["gzh-design"]?.detectedInvocationCount, 1)
        XCTAssertNil(result.records["ignored"])
        XCTAssertEqual(
            result.records["gzh-design"]?.lastDetectedAt,
            Date(timeIntervalSince1970: 1_790_000_200)
        )
    }

    /// OpenCode 2.x stores skill uses in `session_message`; migrated `part` rows must not double count.
    func testScanCountsSessionMessageToolsAndUserSkillMentions() async throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }

        let databaseURL = fixture.root.appendingPathComponent("opencode.db")
        try makeSessionDatabase(at: databaseURL, messages: [
            SessionMessage(
                id: "a1",
                type: "assistant",
                timestamp: 1_790_000_000_000,
                data: [
                    "content": [[
                        "type": "tool",
                        "name": "skill",
                        "state": [
                            "status": "completed",
                            "input": ["name": "web-access"],
                        ],
                    ]],
                ]
            ),
            SessionMessage(
                id: "a2",
                type: "assistant",
                timestamp: 1_790_000_100_000,
                data: [
                    "content": [[
                        "type": "tool",
                        "name": "skill",
                        "state": [
                            "status": "error",
                            "input": ["name": "web-access"],
                        ],
                    ]],
                ]
            ),
            SessionMessage(
                id: "a3",
                type: "assistant",
                timestamp: 1_790_000_200_000,
                data: [
                    "content": [[
                        "type": "tool",
                        "name": "bash",
                        "state": [
                            "status": "completed",
                            "input": ["name": "ignored"],
                        ],
                    ]],
                ]
            ),
            SessionMessage(
                id: "u1",
                type: "user",
                timestamp: 1_790_000_300_000,
                data: [
                    "skills": [
                        ["id": "skilldeck", "name": "skilldeck"],
                        ["id": "skilldeck", "name": "skilldeck"],
                    ],
                ]
            ),
            SessionMessage(
                id: "u2",
                type: "user",
                timestamp: 1_790_000_400_000,
                data: [
                    "text": "skills without an attached skill are just text",
                ]
            ),
        ], legacyRows: [
            Row(
                id: "p1",
                tool: "skill",
                skill: "legacy-only",
                status: "completed",
                timestamp: 1_790_000_500_000
            ),
        ])

        let service = OpenCodeSkillUsageService(databaseURL: databaseURL)
        let result = await service.scan()

        // A modern (non-WAL) database is readable with a strictly read-only handle, so the
        // fallback must never be used here.
        let openMode = await service.lastOpenMode
        XCTAssertEqual(openMode, .readOnly)

        XCTAssertEqual(result.failedLogCount, 0)
        XCTAssertEqual(result.records["web-access"]?.detectedInvocationCount, 1)
        XCTAssertEqual(result.records["skilldeck"]?.detectedInvocationCount, 1)
        XCTAssertEqual(
            result.records["skilldeck"]?.lastDetectedAt,
            Date(timeIntervalSince1970: 1_790_000_300)
        )
        XCTAssertNil(result.records["ignored"])
        XCTAssertNil(result.records["legacy-only"])
    }

    /// Regression test for the permanent OpenCode "usage unreadable" warning.
    ///
    /// OpenCode leaves `opencode.db` in WAL journal mode but deletes `-shm`/`-wal` when it shuts
    /// down. A strictly read-only SQLite connection cannot create the missing wal-index, so the
    /// plain `SQLITE_OPEN_READONLY` open failed with `SQLITE_CANTOPEN` and the scan reported a
    /// failure. The provider must still be able to read such a database.
    func testScanReadsWALDatabaseWhoseSidecarFilesWereRemoved() async throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }

        let databaseURL = fixture.root.appendingPathComponent("opencode.db")
        try makeDatabase(at: databaseURL, rows: [
            Row(id: "p1", tool: "skill", skill: "web-access", status: "completed", timestamp: 1_790_000_000_000),
        ])
        try switchToWALAndDropSidecarFiles(at: databaseURL)

        // Precondition of the bug: SQLite opens the file successfully but fails on the first
        // read, because it cannot create the missing wal-index. Assert that state so this test
        // keeps exercising the fallback instead of silently passing.
        var probe: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(databaseURL.path, &probe, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        if let probe {
            var statement: OpaquePointer?
            XCTAssertNotEqual(
                sqlite3_prepare_v2(probe, "SELECT 1 FROM sqlite_master LIMIT 1", -1, &statement, nil),
                SQLITE_OK,
                "fixture no longer reproduces the WAL/-shm gap"
            )
            sqlite3_finalize(statement)
            sqlite3_close(probe)
        }

        let service = OpenCodeSkillUsageService(databaseURL: databaseURL)
        let result = await service.scan()

        // The wal-index had to be recreated, so the read-write fallback must be the path taken.
        let openMode = await service.lastOpenMode
        XCTAssertEqual(openMode, .readWrite)

        XCTAssertEqual(result.failedLogCount, 0)
        XCTAssertEqual(result.scannedLogCount, 1)
        XCTAssertEqual(result.records["web-access"]?.detectedInvocationCount, 1)
    }

    func testScanReturnsNoCoverageWhenDatabaseIsMissing() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillDeckOpenCodeMissing-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("opencode.db")

        let service = OpenCodeSkillUsageService(databaseURL: missing)
        let result = await service.scan()

        XCTAssertEqual(result.scannedLogCount, 0)
        XCTAssertEqual(result.failedLogCount, 0)
        XCTAssertTrue(result.records.isEmpty)
        let openMode = await service.lastOpenMode
        XCTAssertNil(openMode)
    }

    /// An existing but corrupt database is a read failure, not "no history".
    func testScanReportsUnreadableDatabaseAsFailure() async throws {
        let fixture = try TemporaryFixture()
        defer { fixture.remove() }

        let databaseURL = fixture.root.appendingPathComponent("opencode.db")
        try "not a sqlite database".write(to: databaseURL, atomically: true, encoding: .utf8)

        let service = OpenCodeSkillUsageService(databaseURL: databaseURL)
        let result = await service.scan()

        XCTAssertEqual(result.scannedLogCount, 0)
        XCTAssertEqual(result.failedLogCount, 1)
        XCTAssertTrue(result.records.isEmpty)
        // `SQLITE_NOTADB` is a permanent failure, so both open attempts must be rejected instead
        // of handing a broken connection to the scan. Otherwise a whitelist/blacklist slip in
        // `isReadable` would stay invisible: the result is `.failed` either way.
        let openMode = await service.lastOpenMode
        XCTAssertNil(openMode)
    }

    /// An unreadable parent must not be mistaken for a missing database.
    func testScanReportsInaccessibleDatabaseAsFailure() async throws {
        try XCTSkipIf(getuid() == 0, "Permission checks do not apply when tests run as root")

        let fixture = try TemporaryFixture()
        defer { fixture.remove() }

        let agentDirectory = fixture.root.appendingPathComponent("opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: agentDirectory, withIntermediateDirectories: true)
        let databaseURL = agentDirectory.appendingPathComponent("opencode.db")
        try "unused".write(to: databaseURL, atomically: true, encoding: .utf8)
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

        let service = OpenCodeSkillUsageService(databaseURL: databaseURL)
        let result = await service.scan()

        XCTAssertEqual(result.scannedLogCount, 0)
        XCTAssertEqual(result.failedLogCount, 1)
        XCTAssertTrue(result.records.isEmpty)
        // Neither open mode can reach the file, so no strategy may be reported.
        let openMode = await service.lastOpenMode
        XCTAssertNil(openMode)
    }

    private struct Row {
        let id: String
        let tool: String
        let skill: String
        let status: String
        let timestamp: Int64
    }

    private struct SessionMessage {
        let id: String
        let type: String
        let timestamp: Int64
        let data: [String: Any]
    }

    private func makeDatabase(at url: URL, rows: [Row]) throws {
        let database = try openDatabase(at: url)
        defer { sqlite3_close(database) }
        try execute(
            """
            CREATE TABLE part (
                id TEXT PRIMARY KEY,
                message_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                time_created INTEGER NOT NULL,
                time_updated INTEGER NOT NULL,
                data TEXT NOT NULL
            );
            """,
            in: database
        )
        try insertLegacyRows(rows, into: database)
    }

    private func makeSessionDatabase(
        at url: URL,
        messages: [SessionMessage],
        legacyRows: [Row]
    ) throws {
        let database = try openDatabase(at: url)
        defer { sqlite3_close(database) }
        try execute(
            """
            CREATE TABLE part (
                id TEXT PRIMARY KEY,
                message_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                time_created INTEGER NOT NULL,
                time_updated INTEGER NOT NULL,
                data TEXT NOT NULL
            );
            CREATE TABLE session_message (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                type TEXT NOT NULL,
                seq INTEGER NOT NULL,
                time_created INTEGER NOT NULL,
                time_updated INTEGER NOT NULL,
                data TEXT NOT NULL
            );
            """,
            in: database
        )
        try insertLegacyRows(legacyRows, into: database)

        var statement: OpaquePointer?
        let insertSQL = """
        INSERT INTO session_message (id, session_id, type, seq, time_created, time_updated, data)
        VALUES (?, 'session', ?, 0, ?, ?, ?);
        """
        guard sqlite3_prepare_v2(database, insertSQL, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw NSError(domain: "OpenCodeSkillUsageServiceTests", code: 5)
        }
        defer { sqlite3_finalize(statement) }

        for message in messages {
            let data = try JSONSerialization.data(withJSONObject: message.data, options: [.sortedKeys])
            let json = try XCTUnwrap(String(data: data, encoding: .utf8))

            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, (message.id as NSString).utf8String, -1, Self.transient)
            sqlite3_bind_text(statement, 2, (message.type as NSString).utf8String, -1, Self.transient)
            sqlite3_bind_int64(statement, 3, message.timestamp)
            sqlite3_bind_int64(statement, 4, message.timestamp)
            sqlite3_bind_text(statement, 5, (json as NSString).utf8String, -1, Self.transient)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw NSError(domain: "OpenCodeSkillUsageServiceTests", code: 6)
            }
        }
    }

    /// Moves the fixture database into WAL mode, then removes `-shm`/`-wal` to mimic the state
    /// OpenCode leaves behind after a clean shutdown (WAL header, no sidecar files).
    private func switchToWALAndDropSidecarFiles(at url: URL) throws {
        let database = try openDatabase(at: url)
        try execute("PRAGMA journal_mode = WAL;", in: database)
        // Closing checkpoints the WAL into the main file, so all rows stay readable.
        sqlite3_close(database)
        // The sidecar files may or may not survive the close depending on the SQLite build.
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
    }

    private func openDatabase(at url: URL) throws -> OpaquePointer {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw NSError(domain: "OpenCodeSkillUsageServiceTests", code: 1)
        }
        return database
    }

    private func execute(_ sql: String, in database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "OpenCodeSkillUsageServiceTests", code: 2)
        }
    }

    private func insertLegacyRows(_ rows: [Row], into database: OpaquePointer) throws {
        var statement: OpaquePointer?
        let insertSQL = """
        INSERT INTO part (id, message_id, session_id, time_created, time_updated, data)
        VALUES (?, '', '', ?, ?, ?);
        """
        guard sqlite3_prepare_v2(database, insertSQL, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw NSError(domain: "OpenCodeSkillUsageServiceTests", code: 3)
        }
        defer { sqlite3_finalize(statement) }

        for row in rows {
            let payload: [String: Any] = [
                "type": "tool",
                "tool": row.tool,
                "state": [
                    "status": row.status,
                    "input": ["name": row.skill],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            let json = try XCTUnwrap(String(data: data, encoding: .utf8))

            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, (row.id as NSString).utf8String, -1, Self.transient)
            sqlite3_bind_int64(statement, 2, row.timestamp)
            sqlite3_bind_int64(statement, 3, row.timestamp)
            sqlite3_bind_text(statement, 4, (json as NSString).utf8String, -1, Self.transient)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw NSError(domain: "OpenCodeSkillUsageServiceTests", code: 4)
            }
        }
    }

    private struct TemporaryFixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("SkillDeckOpenCodeTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
