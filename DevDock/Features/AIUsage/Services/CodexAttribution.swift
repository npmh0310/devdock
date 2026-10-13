import Foundation
import SQLite3

/// Who used a Codex quota window: this Mac's own Codex sessions, claude-mem's private
/// Codex, or something this Mac can't see (Codex cloud, another device, a leaked login).
nonisolated struct QuotaAttribution: Sendable, Equatable {
    nonisolated enum Source: Hashable, Sendable {
        /// This Mac's Codex, by client: "VS Code", "CLI", "SDK", …
        case client(String)
        case claudeMem
        case unknown

        var title: String {
            switch self {
            case .client(let name): name
            case .claudeMem: "claude-mem"
            case .unknown: "Unknown"
            }
        }
    }

    nonisolated struct Part: Sendable, Equatable {
        let source: Source
        /// Quota points, 0...1, on the same scale as the window's bar.
        let used: Double
    }

    /// Largest first; sources under half a percent are left out.
    let parts: [Part]
    /// claude-mem's Codex requests in this window.
    let claudeMemRequests: Int

    func used(by source: Source) -> Double {
        parts.first { $0.source == source }?.used ?? 0
    }
}

/// One quota reading, written into the session log with every request this Mac's Codex makes.
nonisolated struct CodexQuotaReading: Sendable {
    let date: Date
    let client: String
    let session: Double
    let sessionResetsAt: Date?
    let weekly: Double
    let weeklyResetsAt: Date?
}

nonisolated enum CodexAttribution {
    /// No request for this long means the client went idle; a rise across the gap was someone else.
    static let idleGap: TimeInterval = 10 * 60
    /// Reset times drift a little between readings of the same window.
    static let sameWindowTolerance: TimeInterval = 10 * 60

    static let windowLengths: [String: TimeInterval] = ["Session": 5 * 3600, "Weekly": 7 * 86400]

    /// Splits a window's usage between sources.
    ///
    /// Readings are moments this Mac's Codex made a request, with the quota right after it.
    /// A rise between two readings close together belongs to that client. A rise across an
    /// idle gap, or since the last reading, belongs to claude-mem when it made requests in
    /// that gap, otherwise to an unknown source. claude-mem requests that overlap your own
    /// sessions count as yours: the quota can't tell them apart.
    static func attribute(window: UsageWindow, length: TimeInterval,
                          readings: [(date: Date, used: Double, client: String)],
                          claudeMemRequests: [Date], now: Date = .now) -> QuotaAttribution? {
        guard let resetsAt = window.resetsAt, resetsAt > now else { return nil }
        let start = resetsAt - length
        let points = readings.filter { $0.date >= start && $0.date <= now }.sorted { $0.date < $1.date }
        let helper = claudeMemRequests.filter { $0 >= start && $0 <= now }.sorted()

        var totals: [QuotaAttribution.Source: Double] = [:]
        var previous: (date: Date, used: Double) = (start, 0)

        func blame(from: Date, to: Date) -> QuotaAttribution.Source {
            helper.contains { $0 > from && $0 <= to } ? .claudeMem : .unknown
        }

        for point in points {
            let rise = max(0, point.used - previous.used)
            if rise > 0 {
                let source: QuotaAttribution.Source = point.date.timeIntervalSince(previous.date) <= idleGap
                    ? .client(point.client)
                    : blame(from: previous.date, to: point.date)
                totals[source, default: 0] += rise
            }
            previous = (point.date, max(previous.used, point.used))
        }
        let rise = max(0, window.used - previous.used)
        if rise > 0 { totals[blame(from: previous.date, to: now), default: 0] += rise }

        let parts = totals
            .filter { $0.value >= 0.005 }
            .map { QuotaAttribution.Part(source: $0.key, used: $0.value) }
            .sorted { $0.used > $1.used }
        return QuotaAttribution(parts: parts, claudeMemRequests: helper.count)
    }
}

// MARK: - Reading the logs

/// Quota readings from `~/.codex/sessions`. Session files reach tens of MB, so each file
/// is read once and then only from where it was left.
actor CodexQuotaLog {
    private struct FileState {
        var offset: UInt64 = 0
        var client = "Codex"
        var readings: [CodexQuotaReading] = []
    }

    private var files: [String: FileState] = [:]

    func readings(since cutoff: Date) -> [CodexQuotaReading] {
        let paths = Self.sessionFiles(modifiedAfter: cutoff)
        files = files.filter { paths.contains($0.key) }
        for path in paths { read(path) }
        return files.values.flatMap(\.readings).filter { $0.date >= cutoff }
    }

    private func read(_ path: String) {
        var state = files[path] ?? FileState()
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < state.offset { state = FileState() }  // Rewritten: start over.
        guard size > state.offset else { files[path] = state; return }

        try? handle.seek(toOffset: state.offset)
        guard let data = try? handle.readToEnd() else { return }
        // Stop at the last full line; a line still being written is read next time.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { files[path] = state; return }
        let chunk = data[data.startIndex...lastNewline]
        state.offset += UInt64(chunk.count)

        for line in chunk.split(separator: UInt8(ascii: "\n")) {
            if state.readings.isEmpty, state.client == "Codex", let client = Self.client(fromMeta: line) {
                state.client = client
            } else if let reading = Self.reading(from: line, client: state.client) {
                state.readings.append(reading)
            }
        }
        files[path] = state
    }

    private static func client(fromMeta line: Data.SubSequence) -> String? {
        guard line.count < 2_000_000,
              let text = String(data: line.prefix(300), encoding: .utf8), text.contains("\"session_meta\""),
              let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              let originator = (entry["payload"] as? [String: Any])?["originator"] as? String
        else { return nil }
        return clientName(originator)
    }

    /// `codex_vscode` → "VS Code".
    static func clientName(_ originator: String) -> String {
        switch originator {
        case "codex_vscode": "VS Code"
        case "codex_cli_rs", "codex_tui": "CLI"
        case "codex_exec": "codex exec"
        case "codex_sdk_ts", "codex_sdk_py": "SDK"
        case let other where other.hasPrefix("codex_"): String(other.dropFirst(6))
        default: originator
        }
    }

    private static let marker = Data("\"rate_limits\"".utf8)

    private static func reading(from line: Data.SubSequence, client: String) -> CodexQuotaReading? {
        guard line.range(of: marker) != nil,
              let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              let limits = (entry["payload"] as? [String: Any])?["rate_limits"] as? [String: Any],
              (limits["limit_id"] as? String ?? "codex") == "codex",
              let primary = limits["primary"] as? [String: Any], let session = primary["used_percent"] as? Double,
              let date = (entry["timestamp"] as? String).flatMap(ISODate.parse)
        else { return nil }
        let secondary = limits["secondary"] as? [String: Any]
        return CodexQuotaReading(
            date: date, client: client,
            session: session / 100,
            sessionResetsAt: (primary["resets_at"] as? Double).map(Date.init(timeIntervalSince1970:)),
            weekly: (secondary?["used_percent"] as? Double ?? 0) / 100,
            weeklyResetsAt: (secondary?["resets_at"] as? Double).map(Date.init(timeIntervalSince1970:)))
    }

    private static func sessionFiles(modifiedAfter cutoff: Date) -> Set<String> {
        let roots = ["sessions", "archived_sessions"].map { "\(CodexUsageClient.home)/\($0)" }
        var paths = Set<String>()
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if (modified ?? .distantPast) >= cutoff { paths.insert(url.path) }
            }
        }
        return paths
    }
}

/// claude-mem runs its own `codex app-server` with a private `CODEX_HOME` in the temp
/// directory, so its requests never show in `~/.codex/sessions`. Its log database has
/// one thread per request.
nonisolated enum ClaudeMemCodex {
    /// Start time of each Codex request claude-mem made since `cutoff`.
    static func requests(since cutoff: Date) -> [Date] {
        let tmp = NSTemporaryDirectory()
        let dirs = ((try? FileManager.default.contentsOfDirectory(atPath: tmp)) ?? [])
            .filter { $0.hasPrefix("claude-mem-codex-app-server-") }
        return dirs.flatMap { dir in
            threadStarts(database: (tmp as NSString).appendingPathComponent("\(dir)/codex-home/logs_2.sqlite"), since: cutoff)
        }
    }

    private static func threadStarts(database path: String, since cutoff: Date) -> [Date] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return [] }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)

        let sql = "SELECT min(ts) FROM logs WHERE ts >= ? AND thread_id IS NOT NULL GROUP BY thread_id"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(cutoff.timeIntervalSince1970))

        var dates: [Date] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            dates.append(Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 0))))
        }
        return dates
    }
}
