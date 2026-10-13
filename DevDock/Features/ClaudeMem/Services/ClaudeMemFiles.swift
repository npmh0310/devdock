import Foundation
import SQLite3

/// claude-mem's settings and `.env` in `~/.claude-mem`.
nonisolated enum ClaudeMemFiles {
    static let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude-mem").path

    static func settings() -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: "\(home)/settings.json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    /// `KEY=value` lines; `export`, quotes and comments are allowed.
    static func env() -> [String: String] {
        guard let text = try? String(contentsOfFile: "\(home)/.env", encoding: .utf8) else { return [:] }
        return parseEnv(text)
    }

    static func parseEnv(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmed
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmed
            var value = line[line.index(after: eq)...].trimmed
            if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }

    /// Newest observation, and how many were written since `start`.
    static func observationStats(since start: Date) -> (last: Date?, count: Int) {
        withDatabase { db in
            var last: Date?
            var count = 0
            var statement: OpaquePointer?
            let sql = "SELECT max(created_at_epoch), sum(created_at_epoch >= ?) FROM observations"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return (nil, 0) }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, Int64(start.timeIntervalSince1970 * 1000))
            if sqlite3_step(statement) == SQLITE_ROW {
                if sqlite3_column_type(statement, 0) != SQLITE_NULL {
                    last = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 0)) / 1000)
                }
                count = Int(sqlite3_column_int64(statement, 1))
            }
            return (last, count)
        } ?? (nil, 0)
    }

    /// Observations claude-mem wrote with a model whose name starts with `prefix`, since each date.
    static func observationCounts(modelPrefix prefix: String, since dates: [Date]) -> [Int] {
        withDatabase { db in observationCounts(db, modelPrefix: prefix, since: dates) } ?? dates.map { _ in 0 }
    }

    private static func observationCounts(_ db: OpaquePointer, modelPrefix prefix: String, since dates: [Date]) -> [Int] {
        let sql = "SELECT count(*) FROM observations WHERE generated_by_model LIKE ? AND created_at_epoch >= ?"
        return dates.map { date in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, "\(prefix)%", -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            // claude-mem stores milliseconds.
            sqlite3_bind_int64(statement, 2, Int64(date.timeIntervalSince1970 * 1000))
            return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
        }
    }

    /// Opens claude-mem's database read-only; it is in use by the worker, so wait briefly on locks.
    private static func withDatabase<T>(_ body: (OpaquePointer) -> T) -> T? {
        var db: OpaquePointer?
        guard sqlite3_open_v2("\(home)/claude-mem.db", &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)
        return body(db)
    }
}

nonisolated private extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
