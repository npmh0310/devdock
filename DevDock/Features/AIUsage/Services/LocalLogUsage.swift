import Foundation

/// Token counts from Claude Code's session logs, for gateway accounts that have no quota API.
nonisolated enum LocalLogUsage {
    // shortcut: rereads every log of the last 7 days each refresh; fine at a few MB,
    // make it incremental like CodexQuotaLog if a gateway account reaches ~100 MB/week.
    static func snapshot(for info: ClaudeAccountInfo, now: Date = .now) -> UsageSnapshot {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!

        var today = 0
        var week = 0
        var seen = Set<String>()
        for file in logFiles(in: "\(info.configDir)/projects", modifiedAfter: weekAgo) {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.contains("\"usage\"") {
                guard let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let message = entry["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any],
                      let date = (entry["timestamp"] as? String).flatMap(ISODate.parse),
                      date >= weekAgo
                else { continue }
                // Streaming writes the same message several times; count it once.
                if let id = message["id"] as? String, !seen.insert(id).inserted { continue }

                let tokens = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
                    .compactMap { usage[$0] as? Int }
                    .reduce(0, +)
                week += tokens
                if date >= startOfToday { today += tokens }
            }
        }

        return UsageSnapshot(
            account: info.account,
            tokenTotals: [TokenTotal(title: "Today", tokens: today), TokenTotal(title: "Last 7 days", tokens: week)],
            updatedAt: now,
            source: .localLogs
        )
    }

    private static func logFiles(in root: String, modifiedAfter cutoff: Date) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
            .filter { url in
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return (modified ?? .distantPast) >= cutoff
            }
            .map(\.path)
    }
}
