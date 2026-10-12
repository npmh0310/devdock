import Foundation

/// Codex (ChatGPT login) quota.
///
/// Live numbers come from the endpoint the Codex app uses, with the token from
/// `~/.codex/auth.json` (kept in memory, never refreshed or stored here). When that
/// fails, the store falls back to the latest `rate_limits` event in the session logs.
nonisolated enum CodexUsageClient {
    static let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
    private static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    static let account = AIAccount(id: home, provider: .codex, name: "Codex", auth: .subscription)

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: "\(home)/auth.json")
    }

    // MARK: - Live

    static func fetchLive() async throws -> UsageSnapshot {
        guard let data = FileManager.default.contents(atPath: "\(home)/auth.json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String
        else { throw UsageError.noCredential }

        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let accountID = tokens["account_id"] as? String {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("DevDock", forHTTPHeaderField: "User-Agent")

        let (body, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401, 403: throw UsageError.tokenExpired
        case 429: throw UsageError.rateLimited
        case let code: throw UsageError.http(code)
        }
        return try parseLive(body)
    }

    static func parseLive(_ data: Data) throws -> UsageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limit = json["rate_limit"] as? [String: Any]
        else { throw UsageError.badResponse }

        let reached = limit["limit_reached"] as? Bool ?? false
        let windows = [("primary_window", "Session"), ("secondary_window", "Weekly")].compactMap { key, title -> UsageWindow? in
            guard let window = limit[key] as? [String: Any], let percent = window["used_percent"] as? Double else { return nil }
            let resetsAt = (window["reset_at"] as? Double).map(Date.init(timeIntervalSince1970:))
            return UsageWindow(title: title, used: percent / 100, resetsAt: resetsAt,
                               note: reached && percent >= 100 ? "Limit reached" : nil)
        }
        guard !windows.isEmpty else { throw UsageError.badResponse }

        return UsageSnapshot(account: account, plan: (json["plan_type"] as? String)?.capitalized,
                             windows: windows, updatedAt: .now, source: .officialAPI)
    }

    // MARK: - Session logs

    /// Latest `token_count` event with Codex limits from the newest session files.
    static func fromSessionLogs() -> UsageSnapshot? {
        for file in recentSessionFiles(limit: 5) {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
                guard let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let limits = (entry["payload"] as? [String: Any])?["rate_limits"] as? [String: Any],
                      limits["primary"] is [String: Any]
                else { continue }

                let windows = [("primary", "Session"), ("secondary", "Weekly")].compactMap { key, title -> UsageWindow? in
                    guard let window = limits[key] as? [String: Any], let percent = window["used_percent"] as? Double else { return nil }
                    let resetsAt = (window["resets_at"] as? Double).map(Date.init(timeIntervalSince1970:))
                    // The log can be older than the window: once it reset, usage starts from zero.
                    let used = (resetsAt.map { $0 < .now } ?? false) ? 0 : percent / 100
                    return UsageWindow(title: title, used: used, resetsAt: resetsAt)
                }
                return UsageSnapshot(account: account, plan: (limits["plan_type"] as? String)?.capitalized,
                                     windows: windows,
                                     updatedAt: (entry["timestamp"] as? String).flatMap(ISODate.parse),
                                     source: .localLogs)
            }
        }
        return nil
    }

    /// Session files live in `sessions/YYYY/MM/DD/`; walk the newest days first.
    private static func recentSessionFiles(limit: Int) -> [String] {
        let fm = FileManager.default
        let root = "\(home)/sessions"
        func sortedDesc(_ path: String) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: path)) ?? []).sorted(by: >).map { "\(path)/\($0)" }
        }
        var files: [String] = []
        for year in sortedDesc(root) {
            for month in sortedDesc(year) {
                for day in sortedDesc(month) {
                    let jsonl = sortedDesc(day).filter { $0.hasSuffix(".jsonl") }
                    let byDate = jsonl.sorted {
                        let a = (try? fm.attributesOfItem(atPath: $0)[.modificationDate] as? Date) ?? .distantPast
                        let b = (try? fm.attributesOfItem(atPath: $1)[.modificationDate] as? Date) ?? .distantPast
                        return a > b
                    }
                    files += byDate
                    if files.count >= limit { return Array(files.prefix(limit)) }
                }
            }
        }
        return files
    }
}
