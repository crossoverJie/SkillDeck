import Foundation
import SQLite3

/// Recovers skill invocations from OpenCode's local SQLite database.
///
/// OpenCode 2.x writes messages to `session_message`, where a skill use appears either as a
/// completed `skill` tool part or, in newer releases, as a `skills` entry on a user message
/// created by an `@skill` mention. `session_message` also contains migrated history, so it is
/// preferred over the legacy `part` table whenever it has rows; querying both would double count.
/// Legacy 1.x JSON files under `storage/part/` are intentionally ignored because current
/// OpenCode versions no longer write there.
actor OpenCodeSkillUsageService: SkillUsageProvider {
    nonisolated var agentType: AgentType { .openCode }

    private let databaseURL: URL

    /// Production initializer based on the current macOS user's home directory.
    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.databaseURL = homeDirectory
            .appendingPathComponent(".local/share/opencode/opencode.db", isDirectory: false)
    }

    /// Test initializer that points at a temporary SQLite fixture.
    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    func scan() -> SkillUsageScanResult {
        // Reset before doing anything so a scan that never reaches an open (missing path, path
        // probe failure, both open attempts failing) cannot report the previous attempt's strategy.
        lastOpenMode = nil

        switch SkillUsagePathProbe.status(at: databaseURL) {
        case .missing:
            return SkillUsageScanResult(
                records: [:], scannedLogCount: 0, preservedLogCount: 0, failedLogCount: 0
            )
        case .directory, .inaccessible:
            // The path exists but cannot be a readable database, or its parent cannot be
            // inspected. Report a failure instead of claiming there is no history.
            return Self.failure
        case .notDirectory:
            break
        }

        guard let database = openForReading() else {
            return Self.failure
        }
        defer { sqlite3_close(database) }

        let rows: [SkillRow]
        if tableExists("session_message", in: database),
           tableHasRows("session_message", in: database) {
            guard let sessionRows = readSessionMessageRows(from: database) else {
                return Self.failure
            }
            rows = sessionRows
        } else if tableExists("part", in: database) {
            guard let legacyRows = readLegacyPartRows(from: database) else {
                return Self.failure
            }
            rows = legacyRows
        } else {
            // The file is a database, but not one this provider understands.
            return Self.failure
        }

        var records: [String: MutableSkillUsageRecord] = [:]
        for row in rows where row.status == "completed" {
            var record = records[row.skillID] ?? MutableSkillUsageRecord()
            record.detectedInvocationCount += 1
            if let timestamp = row.timestamp,
               record.lastDetectedAt == nil || timestamp > record.lastDetectedAt! {
                record.lastDetectedAt = timestamp
            }
            records[row.skillID] = record
        }

        return SkillUsageScanResult(
            records: records.mapValues {
                SkillUsageRecord(
                    detectedInvocationCount: $0.detectedInvocationCount,
                    lastDetectedAt: $0.lastDetectedAt
                )
            },
            scannedLogCount: 1,
            preservedLogCount: 0,
            failedLogCount: 0
        )
    }

    private static let failure = SkillUsageScanResult(
        // Report zero readable coverage so the manager maps this to `.failed` instead of
        // `.available` with "no usage detected".
        records: [:], scannedLogCount: 0, preservedLogCount: 0, failedLogCount: 1
    )

    /// How the current connection was opened. Exposed for tests and diagnostics so the
    /// "prefer read-only" contract stays observable instead of silently rotting.
    ///
    /// It records only the opening strategy of the last scan attempt, not its outcome: it is
    /// `nil` while no scan ran and whenever both open attempts failed, but it stays set when the
    /// handle opened fine and a *later* query (e.g. `readSessionMessageRows`) failed.
    ///
    /// `private(set)` keeps it read-only for everyone outside this actor (Swift's equivalent of a
    /// getter-only property in Java), while the actor still mutates it in `openForReading()`.
    private(set) var lastOpenMode: DatabaseOpenMode?

    /// Journal-mode-safe opening strategy chosen for a scan.
    enum DatabaseOpenMode: Equatable, Sendable {
        /// Opened with `SQLITE_OPEN_READONLY`, which cannot create a `-shm` file.
        case readOnly
        /// Opened with `SQLITE_OPEN_READWRITE` (no CREATE) so SQLite may build the wal-index.
        case readWrite
    }

    /// Opens the database for reading, degrading to a read-write handle only when SQLite refuses
    /// a strictly read-only connection.
    ///
    /// Why the fallback is required: OpenCode keeps `opencode.db` in WAL journal mode (the header
    /// records `read/write version 2`). A WAL database needs its `-shm` wal-index file before any
    /// page can be read, and a connection opened with `SQLITE_OPEN_READONLY` is not permitted to
    /// create that file. When OpenCode shuts down cleanly, SQLite checkpoints the WAL and deletes
    /// `-shm`/`-wal`; the very next read-only open then fails with `SQLITE_CANTOPEN` ("unable to
    /// open database file") even though the file is perfectly readable. Result: every OpenCode
    /// usage scan reported a read failure and the UI showed a permanent warning triangle.
    ///
    /// The `SQLITE_OPEN_READWRITE` retry (deliberately *without* `SQLITE_OPEN_CREATE`) lets SQLite
    /// recreate the wal-index, which is the same thing any OpenCode or `sqlite3` process does.
    ///
    /// Side effects of the fallback, stated explicitly because they are not "zero writes": the
    /// `-shm` wal-index appears in `~/.local/share/opencode/`, and when this handle is the last
    /// connection to close, SQLite may checkpoint the WAL back into `opencode.db`. Neither touches
    /// stored rows, both are ordinary SQLite behaviour, and OpenCode simply reuses or recreates
    /// those files on its next start — but nothing here should be described as read-only.
    ///
    /// Note that `sqlite3_open_v2` reports success for such a database and only fails later, on the
    /// first page read, so the handle is probed with a trivial query before being trusted.
    private func openForReading() -> OpaquePointer? {
        // Preferred path: strictly read-only, used whenever `-shm` already exists. This is the
        // only path that is safe on a database the current user cannot write to.
        if let database = open(flags: SQLITE_OPEN_READONLY) {
            if isReadable(database) {
                lastOpenMode = .readOnly
                return database
            }
            // Opened but unusable (missing wal-index); free the handle before retrying.
            sqlite3_close(database)
        }

        // Fallback path: read-write (no CREATE) so the `-shm` wal-index can be recreated.
        guard let database = open(flags: SQLITE_OPEN_READWRITE) else {
            return nil
        }
        // Verify both paths the same way: an unusable fallback handle must become a reported
        // failure instead of a stream of confusing errors from the individual queries.
        guard isReadable(database) else {
            sqlite3_close(database)
            return nil
        }
        lastOpenMode = .readWrite
        return database
    }

    /// Forces a page read to prove the connection can be used for the upcoming queries.
    ///
    /// `SELECT 1 FROM sqlite_master LIMIT 1` only needs the schema page, so it is cheap even for a
    /// multi-gigabyte database, but preparing it already triggers the page read that a read-only
    /// WAL connection cannot perform without a wal-index.
    ///
    /// The check is a whitelist, not a blacklist: only `SQLITE_OK` and the temporary
    /// `SQLITE_BUSY`/`SQLITE_LOCKED` states count as usable. Every other error
    /// (`CANTOPEN`, `READONLY`, `IOERR`, `NOTADB`, `CORRUPT`, …) is treated as a permanent failure
    /// of this handle, so the caller retries with the other open mode. Do not invert this into
    /// "unusable == CANTOPEN": the error SQLite reports for a WAL database without a wal-index
    /// varies by SQLite version, file system and permissions (observed `CANTOPEN` on 3.51.0, no
    /// error at all on 3.53.4, `READONLY` for a write-protected directory), and any unlisted code
    /// would then silently skip the fallback and reintroduce the permanent warning triangle.
    ///
    /// `SQLITE_BUSY`/`SQLITE_LOCKED` are the exception because another process (a running OpenCode)
    /// holds a transient lock: downgrading to read-write just to create sidecar files would not
    /// help, and the queries that follow already wait for the busy timeout.
    private func isReadable(_ database: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(
            database, "SELECT 1 FROM sqlite_master LIMIT 1", -1, &statement, nil
        )
        sqlite3_finalize(statement)
        return status == SQLITE_OK || status == SQLITE_BUSY || status == SQLITE_LOCKED
    }

    /// Thin wrapper around `sqlite3_open_v2` that applies the busy timeout and releases the handle
    /// on failure.
    ///
    /// The timeout is set here, immediately after a successful open, so the availability probe in
    /// `openForReading()` also waits for a short-lived writer lock instead of reporting a spurious
    /// failure.
    ///
    /// `flags` is `Int32` because the C API declares the parameter as `int`; Swift imports C
    /// `int` as `Int32` (not the platform-sized `Int` used by most Swift APIs).
    private func open(flags: Int32) -> OpaquePointer? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            // SQLite may allocate a handle even when opening fails; close it to avoid leaking
            // one connection per refresh attempt against a corrupt or unreadable database.
            if let database {
                sqlite3_close(database)
            }
            return nil
        }
        // Give any competing writer (a running OpenCode) a chance to finish before failing.
        sqlite3_busy_timeout(database, 2_000)
        return database
    }

    private func tableExists(_ name: String, in database: OpaquePointer) -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, Self.transient)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func tableHasRows(_ name: String, in database: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT 1 FROM \(name) LIMIT 1", -1, &statement, nil)
                == SQLITE_OK,
              let statement else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func readSessionMessageRows(from database: OpaquePointer) -> [SkillRow]? {
        let sql = """
        SELECT time_created, type, data
        FROM session_message
        WHERE type IN ('assistant', 'user') AND data LIKE '%skill%'
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var rows: [SkillRow] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE {
                return rows
            }
            guard step == SQLITE_ROW else {
                return nil
            }
            guard let typeText = sqlite3_column_text(statement, 1),
                  let dataText = sqlite3_column_text(statement, 2) else {
                continue
            }

            let createdAt = sqlite3_column_int64(statement, 0)
            let timestamp = createdAt > 0
                ? Date(timeIntervalSince1970: Double(createdAt) / 1000)
                : nil
            let type = String(cString: typeText)
            let data = String(cString: dataText)

            guard let jsonData = data.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else {
                continue
            }

            switch type {
            case "assistant":
                for content in object["content"] as? [[String: Any]] ?? [] {
                    guard content["type"] as? String == "tool",
                          content["name"] as? String == "skill",
                          let state = content["state"] as? [String: Any],
                          state["status"] as? String == "completed",
                          let input = state["input"] as? [String: Any],
                          let skillID = input["name"] as? String,
                          !skillID.isEmpty else {
                        continue
                    }
                    rows.append(SkillRow(
                        skillID: skillID,
                        status: "completed",
                        timestamp: timestamp
                    ))
                }
            case "user":
                guard let skills = object["skills"] as? [[String: Any]] else { continue }
                var seen: Set<String> = []
                for skill in skills {
                    guard let skillID = (skill["id"] as? String) ?? (skill["name"] as? String),
                          !skillID.isEmpty,
                          seen.insert(skillID).inserted else {
                        continue
                    }
                    rows.append(SkillRow(
                        skillID: skillID,
                        status: "completed",
                        timestamp: timestamp
                    ))
                }
            default:
                continue
            }
        }
    }

    private func readLegacyPartRows(from database: OpaquePointer) -> [SkillRow]? {
        let sql = """
        SELECT json_extract(data, '$.state.input.name'),
               json_extract(data, '$.state.status'),
               time_created
        FROM part
        WHERE json_extract(data, '$.tool') = 'skill'
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var rows: [SkillRow] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE {
                return rows
            }
            guard step == SQLITE_ROW else {
                return nil
            }
            guard let nameText = sqlite3_column_text(statement, 0),
                  let statusText = sqlite3_column_text(statement, 1) else {
                continue
            }

            let skillID = String(cString: nameText)
            guard !skillID.isEmpty else { continue }

            let createdAt = sqlite3_column_int64(statement, 2)
            rows.append(SkillRow(
                skillID: skillID,
                status: String(cString: statusText),
                timestamp: createdAt > 0
                    ? Date(timeIntervalSince1970: Double(createdAt) / 1000)
                    : nil
            ))
        }
    }

    private struct SkillRow {
        let skillID: String
        let status: String
        let timestamp: Date?
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
