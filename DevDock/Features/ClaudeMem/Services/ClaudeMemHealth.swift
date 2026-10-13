import Darwin
import Foundation

/// Everything DevDock can see about claude-mem's background worker, read from
/// `~/.claude-mem` and the worker's local health endpoint. Never reads keys.
nonisolated struct ClaudeMemSignals: Sendable, Equatable {
    struct Worker: Sendable, Equatable {
        let pid: Int32
        let port: Int
        let startedAt: Date?
        var version: String?
        /// The health endpoint answered.
        var isResponding = false
        var isDegraded = false
    }

    struct ObserverError: Sendable, Equatable {
        let date: Date
        let message: String
        let kind: String?
        let code: String?
        /// claude-mem's own advice, e.g. "Raise CLAUDE_MEM_LLM_TIMEOUT_MS …".
        let action: String?
        let provider: String?
    }

    /// Settings say claude-mem is installed and has a provider.
    var isInstalled = false
    var provider: String?
    var model: String?
    /// Nil when no pid file or the process is gone.
    var worker: Worker?
    var consecutiveFailures = 0
    var failingSince: Date?
    var lastSuccess: Date?
    var lastError: ObserverError?
    /// claude-mem paused itself after the provider reported its quota used up.
    var cooldown: String?
    var lastObservation: Date?
    var observationsToday = 0
    /// Hook events waiting for the worker; old ones are leftovers it keeps.
    var queued = 0
    var oldestQueued: Date?
    /// Newest Claude Code transcript write: when the user was last working.
    var lastActivity: Date?
    /// The prepaid provider ran out of credit (from the AI usage module).
    var outOfCredit = false
}

nonisolated struct ClaudeMemAssessment: Sendable, Equatable {
    enum Status: Int, Comparable, Sendable {
        case ok, lagging, down
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let status: Status
    /// One line: why it is not ok, or what it last did.
    let summary: String
    /// What to do about it.
    var fix: String?
}

nonisolated enum ClaudeMemHealth {
    /// Working this long after the last saved memory counts as lagging.
    static let lagThreshold: TimeInterval = 30 * 60
    /// Failing this long, or this many times in a row, counts as down.
    static let downAfter: TimeInterval = 10 * 60
    static let downAfterFailures = 3

    static func assess(_ s: ClaudeMemSignals, now: Date = .now) -> ClaudeMemAssessment {
        guard s.isInstalled else { return .init(status: .ok, summary: "Not installed") }

        guard let worker = s.worker, worker.isResponding else {
            return .init(status: .down,
                         summary: s.worker == nil ? "Worker is not running" : "Worker is not responding",
                         fix: "Start a Claude Code session: its hooks start the worker again.")
        }
        if s.outOfCredit {
            return .init(status: .down, summary: "\(providerName(s)) balance used up",
                         fix: "Top up, or switch CLAUDE_MEM_PROVIDER in ~/.claude-mem/settings.json.")
        }
        if let cooldown = s.cooldown {
            return .init(status: .down, summary: "Paused: \(cooldown)",
                         fix: "It resumes on its own when the quota resets, or switch its provider.")
        }
        let failingFor = s.failingSince.map { now.timeIntervalSince($0) } ?? 0
        if s.consecutiveFailures >= downAfterFailures || (s.consecutiveFailures > 0 && failingFor >= downAfter) {
            return .init(status: .down, summary: errorSummary(s), fix: s.lastError?.action)
        }
        if s.consecutiveFailures > 0 {
            return .init(status: .lagging, summary: errorSummary(s), fix: s.lastError?.action)
        }
        if let activity = s.lastActivity, now.timeIntervalSince(activity) < lagThreshold,
           activity.timeIntervalSince(s.lastObservation ?? .distantPast) >= lagThreshold {
            let since = s.lastObservation.map { "since \(RelativeTime.ago($0, now: now))" } ?? "yet"
            return .init(status: .lagging, summary: "You're working but nothing was saved \(since)",
                         fix: "Check the log for errors; restarting Claude Code restarts the worker.")
        }
        if worker.isDegraded {
            return .init(status: .lagging, summary: "Worker reports degraded dependencies", fix: "Check the log.")
        }
        return .init(status: .ok, summary: s.lastObservation.map { "Saved \(RelativeTime.ago($0, now: now))" } ?? "Nothing saved yet")
    }

    private static func errorSummary(_ s: ClaudeMemSignals) -> String {
        let times = s.consecutiveFailures == 1 ? "1 failure" : "\(s.consecutiveFailures) failures in a row"
        guard let message = s.lastError?.message else { return times }
        return "\(times): \(message)"
    }

    static func providerName(_ s: ClaudeMemSignals) -> String {
        let known = ["deepseek": "DeepSeek", "openrouter": "OpenRouter", "codex": "Codex", "claude": "Claude", "gemini": "Gemini"]
        switch s.provider {
        case "openai-compatible":
            // The model names the vendor: "deepseek-chat" → DeepSeek.
            let vendor = s.model?.split(separator: "-").first.map { String($0).lowercased() }
            return vendor.map { known[$0] ?? $0.capitalized } ?? "OpenAI-compatible"
        case let provider?: return known[provider] ?? provider.capitalized
        case nil: return "Provider"
        }
    }

    // MARK: - Reading

    static func read(outOfCredit: Bool) async -> ClaudeMemSignals {
        var s = await Task.detached { readFiles() }.value
        s.outOfCredit = outOfCredit
        if var worker = s.worker, let health = await fetchHealth(port: worker.port) {
            worker.isResponding = health.status == "ok"
            worker.version = health.version
            worker.isDegraded = health.degraded
            s.worker = worker
        }
        return s
    }

    private static func readFiles() -> ClaudeMemSignals {
        let home = ClaudeMemFiles.home
        var s = ClaudeMemSignals()
        let settings = ClaudeMemFiles.settings()
        let text = { (key: String) in (settings[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        s.isInstalled = FileManager.default.fileExists(atPath: "\(home)/settings.json")
        s.provider = text("CLAUDE_MEM_PROVIDER")
        s.model = s.provider == "openai-compatible"
            ? text("CLAUDE_MEM_OPENAI_COMPAT_MODEL") ?? text("CLAUDE_MEM_OPENAI_COMPAT_PRESET")
            : s.provider == "codex" ? text("CLAUDE_MEM_CODEX_MODEL") : nil

        if let pidFile = json("\(home)/worker.pid"), let pid = (pidFile["pid"] as? NSNumber)?.int32Value,
           let port = (pidFile["port"] as? NSNumber)?.intValue, Darwin.kill(pid, 0) == 0 {
            s.worker = .init(pid: pid, port: port, startedAt: (pidFile["startedAt"] as? String).flatMap(ISODate.parse))
        }

        if let health = json("\(home)/observer-health.json") {
            s.consecutiveFailures = (health["consecutiveFailures"] as? NSNumber)?.intValue ?? 0
            s.failingSince = millis(health["failingSinceAt"])
            s.lastSuccess = millis(health["lastSuccessAt"])
            if let date = millis(health["lastErrorAt"]), let message = health["lastErrorMessage"] as? String {
                s.lastError = .init(date: date, message: message, kind: health["lastErrorKind"] as? String,
                                    code: health["lastErrorCode"] as? String, action: health["lastErrorAction"] as? String,
                                    provider: health["lastErrorProvider"] as? String)
            }
            s.cooldown = cooldownText(health["quotaCooldown"])
        }

        let today = Calendar.current.startOfDay(for: .now)
        let (last, count) = ClaudeMemFiles.observationStats(since: today)
        s.lastObservation = last
        s.observationsToday = count

        let spool = "\(home)/state/hook-spool"
        let queued = ((try? FileManager.default.contentsOfDirectory(atPath: spool)) ?? []).filter { $0.hasSuffix(".json") }
        s.queued = queued.count
        s.oldestQueued = queued.compactMap { modified("\(spool)/\($0)") }.min()
        s.lastActivity = ProjectScanner.claudeSessions().values.max()
        return s
    }

    /// `quotaCooldown` is null, a string, or an object with a provider and window.
    private static func cooldownText(_ value: Any?) -> String? {
        switch value {
        case let text as String where !text.isEmpty: return text
        case let object as [String: Any]:
            let parts = [object["provider"], object["window"]].compactMap { $0 as? String }
            return parts.isEmpty ? "quota cooldown" : "\(parts.joined(separator: " ")) quota cooldown"
        default: return nil
        }
    }

    private struct HealthResponse: Decodable {
        let status: String
        let version: String?
        let dependencies: Dependencies?
        struct Dependencies: Decodable { let degraded: Bool? }
        var degraded: Bool { dependencies?.degraded ?? false }
    }

    private static func fetchHealth(port: Int) async -> HealthResponse? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/health") else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 3)),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONDecoder().decode(HealthResponse.self, from: data)
    }

    private static func json(_ path: String) -> [String: Any]? {
        FileManager.default.contents(atPath: path).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    private static func millis(_ value: Any?) -> Date? {
        (value as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
    }

    private static func modified(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
