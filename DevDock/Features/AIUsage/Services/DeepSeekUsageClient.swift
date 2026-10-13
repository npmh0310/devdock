import Foundation

/// DeepSeek balance, for the API key claude-mem's memory observer runs on.
///
/// DeepSeek has no quota windows, only a prepaid balance. The key is read the way
/// claude-mem reads it (`CLAUDE_MEM_OPENAI_COMPAT_API_KEY` in `~/.claude-mem/settings.json`,
/// else `OPENAI_COMPAT_API_KEY` in `~/.claude-mem/.env`), kept in memory for the request
/// only, and never logged or stored.
nonisolated enum DeepSeekUsageClient {
    private static let endpoint = URL(string: "https://api.deepseek.com/user/balance")!
    static let topUpURL = URL(string: "https://platform.deepseek.com/top_up")!
    static let usageURL = URL(string: "https://platform.deepseek.com/usage")!

    static let account = AIAccount(id: "deepseek", provider: .deepseek, name: "DeepSeek", auth: .prepaid)

    struct Config: Sendable {
        let model: String?
        fileprivate let apiKey: String?
    }

    /// Set when claude-mem's provider is DeepSeek (its preset, or a DeepSeek base URL).
    static func config() -> Config? {
        let settings = ClaudeMemFiles.settings()
        let text = { (key: String) in (settings[key] as? String).flatMap { $0.trimmed.isEmpty ? nil : $0.trimmed } }
        guard text("CLAUDE_MEM_PROVIDER") == "openai-compatible",
              text("CLAUDE_MEM_OPENAI_COMPAT_PRESET") == "deepseek"
                || text("CLAUDE_MEM_OPENAI_COMPAT_BASE_URL")?.contains("deepseek.com") == true
        else { return nil }

        let env = ClaudeMemFiles.env()
        let key = text("CLAUDE_MEM_OPENAI_COMPAT_API_KEY") ?? env["OPENAI_COMPAT_API_KEY"]
            ?? (text("CLAUDE_MEM_OPENAI_COMPAT_API_KEYS") ?? env["OPENAI_COMPAT_API_KEYS"])
                .flatMap { $0.split(separator: ",").first.map { String($0).trimmed } }
        return Config(model: text("CLAUDE_MEM_OPENAI_COMPAT_MODEL") ?? "deepseek-chat",
                      apiKey: key.flatMap { $0.isEmpty ? nil : $0 })
    }

    static func fetch(_ config: Config) async throws -> UsageSnapshot {
        guard let key = config.apiKey else { throw UsageError.noCredential }

        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (body, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401, 403: throw UsageError.tokenExpired
        case 429: throw UsageError.rateLimited
        case let code: throw UsageError.http(code)
        }
        var snapshot = UsageSnapshot(account: account, plan: config.model, updatedAt: .now, source: .officialAPI)
        snapshot.balance = try parseBalance(body)
        return snapshot
    }

    /// `{"is_available": true, "balance_infos": [{"currency": "USD", "total_balance": "4.20", ...}]}`.
    /// Amounts are strings; the USD entry wins when there are several currencies.
    static func parseBalance(_ data: Data) throws -> Balance {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let infos = json["balance_infos"] as? [[String: Any]],
              let info = infos.first(where: { $0["currency"] as? String == "USD" }) ?? infos.first,
              let currency = info["currency"] as? String,
              let total = amount(info["total_balance"])
        else { throw UsageError.badResponse }
        return Balance(currency: currency, total: total,
                       granted: amount(info["granted_balance"]) ?? 0,
                       toppedUp: amount(info["topped_up_balance"]) ?? 0,
                       isAvailable: json["is_available"] as? Bool ?? (total > 0))
    }

    /// The balance as a quota, so it warns and shows like the other accounts: used is the
    /// share spent of what there was after the last top-up. Out of credit counts as full.
    static func window(_ balance: Balance, reference: Double?) -> UsageWindow {
        guard balance.isAvailable else { return UsageWindow(title: "Balance", used: 1, note: "Used up") }
        guard let reference, reference > 0 else { return UsageWindow(title: "Balance", used: 0) }
        return UsageWindow(title: "Balance", used: min(max(1 - balance.total / reference, 0), 1))
    }

    private static func amount(_ value: Any?) -> Double? {
        if let string = value as? String { return Double(string) }
        return (value as? NSNumber)?.doubleValue
    }
}

/// What claude-mem did with DeepSeek, and what it cost.
nonisolated struct PrepaidActivity: Sendable, Equatable {
    var observationsToday = 0
    var observationsWeek = 0
    var spentToday: Double?
    var spentWeek: Double?
    /// First balance reading, when it is newer than the start of the week: spend before it is unknown.
    var trackedSince: Date?
    /// Balance right after the last top-up, or the first reading when no top-up was seen.
    var reference: Double?
}

/// Balance readings over time. DeepSeek has no usage API for API keys, so spend is
/// the sum of the drops between readings; a top-up (a rise) is not counted.
nonisolated struct BalanceLog {
    struct Reading: Codable, Equatable {
        let date: Date
        let total: Double
    }

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DevDock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("deepseek-balance.json")
    }()

    func load() -> [Reading] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Reading].self, from: data)) ?? []
    }

    /// Adds a reading when the balance changed, keeping five weeks.
    func record(_ total: Double, at date: Date = .now) -> [Reading] {
        var readings = load()
        if readings.last?.total != total {
            readings.append(Reading(date: date, total: total))
            readings.removeAll { $0.date < date - 35 * 86400 }
            if let data = try? JSONEncoder().encode(readings) { try? data.write(to: url, options: .atomic) }
        }
        return readings
    }

    /// Balance right after the latest top-up (a rise), else the first reading.
    static func reference(_ readings: [Reading]) -> Double? {
        guard let first = readings.first else { return nil }
        return zip(readings, readings.dropFirst()).reduce(first.total) { $1.1.total > $1.0.total ? $1.1.total : $0 }
    }

    /// Spend since `start`, counted from the last reading before it (or the first one there is).
    static func spent(_ readings: [Reading], since start: Date) -> Double? {
        guard !readings.isEmpty else { return nil }
        let window = readings[(readings.lastIndex { $0.date <= start } ?? 0)...]
        return zip(window, window.dropFirst()).reduce(0) { $0 + max(0, $1.0.total - $1.1.total) }
    }
}

nonisolated private extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
