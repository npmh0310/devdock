import Defaults
import Foundation
import Observation

/// Usage for every AI account. Each account is fetched on its own, so one failing
/// (expired login, network) never hides the others.
@Observable
final class AIUsageStore {
    private(set) var accounts: [AIAccount] = []
    private(set) var snapshots: [AIAccount.ID: UsageSnapshot] = [:]
    /// Why the latest fetch failed. The last good snapshot (if any) is still shown.
    private(set) var errors: [AIAccount.ID: UsageError] = [:]
    private(set) var hasLoaded = false
    /// Who used each Codex window, by window title.
    private(set) var codexAttribution: [UsageWindow.ID: QuotaAttribution] = [:]
    /// claude-mem's DeepSeek observations and the spend seen in the balance.
    private(set) var deepSeekActivity: PrepaidActivity?

    /// Called after every refresh, also when nothing was due, so time-based state
    /// (a window passing its reset time) is re-evaluated.
    @ObservationIgnored var onUpdate: (() -> Void)?

    @ObservationIgnored private var lastAPIFetch: [AIAccount.ID: Date] = [:]
    /// The panel tick and the background loop both refresh; never let them overlap.
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private let cache = UsageCache()
    @ObservationIgnored private let history = UsageHistory()
    @ObservationIgnored private let codexLog = CodexQuotaLog()
    @ObservationIgnored private let balanceLog = BalanceLog()

    init() {
        snapshots = cache.load()
        // The last good readings count as history, so the pace shows up sooner after a restart.
        snapshots.values.forEach(history.record)
    }

    /// Where a window is heading at the recent rate of use. Nil until there is enough history.
    func pace(for account: AIAccount, window: UsageWindow) -> UsagePace? {
        history.pace(accountID: account.id, window: window)
    }

    func refresh(force: Bool = false) async {
        // A refresh is already running: wait for it. A forced one (refresh button) runs after it.
        if let inFlight {
            await inFlight.value
            if !force { return }
        }
        let task = Task { await performRefresh(force: force) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func performRefresh(force: Bool) async {
        let claude = await Task.detached { ClaudeAccountDiscovery.discover() }.value
        let hasCodex = CodexUsageClient.isInstalled
        let deepSeek = await Task.detached { DeepSeekUsageClient.config() }.value
        accounts = claude.map(\.account) + (hasCodex ? [CodexUsageClient.account] : [])
            + (deepSeek != nil ? [DeepSeekUsageClient.account] : [])

        let due = claude.filter { isDue($0.account.id, force: force) }

        await withTaskGroup(of: (AIAccount.ID, Result<UsageSnapshot, UsageError>).self) { group in
            for info in due {
                group.addTask {
                    switch info.account.auth {
                    case .subscription: return (info.account.id, await Self.capture { try await ClaudeUsageClient.fetch(info) })
                    case .gateway, .prepaid: return (info.account.id, .success(LocalLogUsage.snapshot(for: info)))
                    }
                }
            }
            if hasCodex, isDue(CodexUsageClient.account.id, force: force) {
                group.addTask { (CodexUsageClient.account.id, await Self.capture { try await CodexUsageClient.fetchLive() }) }
            }
            if let deepSeek, isDue(DeepSeekUsageClient.account.id, force: force) {
                group.addTask { (DeepSeekUsageClient.account.id, await Self.capture { try await DeepSeekUsageClient.fetch(deepSeek) }) }
            }
            for await (id, result) in group {
                lastAPIFetch[id] = .now
                switch result {
                case .success(let snapshot):
                    snapshots[id] = snapshot
                    errors[id] = nil
                    history.record(snapshot)
                case .failure(let error):
                    errors[id] = error
                    if id == CodexUsageClient.account.id { await useCodexLogsIfNewer() }
                }
            }
        }

        if hasCodex, let snapshot = snapshots[CodexUsageClient.account.id] {
            codexAttribution = await Self.attribute(snapshot, log: codexLog)
        }

        if deepSeek != nil {
            let id = DeepSeekUsageClient.account.id
            let activity = await Self.deepSeekActivity(balance: snapshots[id]?.balance, log: balanceLog)
            deepSeekActivity = activity
            if let balance = snapshots[id]?.balance {
                snapshots[id]?.windows = [DeepSeekUsageClient.window(balance, reference: activity.reference)]
            }
        }

        cache.save(snapshots)
        hasLoaded = true
        onUpdate?()
    }

    /// Throttled by the "Update AI usage every" setting. The cached snapshot counts too,
    /// so restarting the app doesn't trigger a request either.
    private func isDue(_ id: AIAccount.ID, force: Bool) -> Bool {
        guard !force else { return true }
        let interval = TimeInterval(max(Defaults[.aiUsageInterval], 1) * 60)
        let cached = snapshots[id].flatMap { $0.source == .officialAPI ? $0.updatedAt : nil }
        let last = max(lastAPIFetch[id] ?? .distantPast, cached ?? .distantPast)
        return Date.now.timeIntervalSince(last) >= interval
    }

    /// Codex writes its limits into every session log, so they are a good fallback
    /// while the live request fails (expired login, offline).
    private func useCodexLogsIfNewer() async {
        let id = CodexUsageClient.account.id
        // Same incremental reader the attribution uses, so nothing is read twice.
        guard let latest = await codexLog.readings(since: .now - 7 * 86400).max(by: { $0.date < $1.date }) else { return }
        let logged = CodexUsageClient.snapshot(from: latest, plan: snapshots[id]?.plan)
        if (logged.updatedAt ?? .distantPast) > (snapshots[id]?.updatedAt ?? .distantPast) {
            snapshots[id] = logged
            history.record(logged)
        }
    }

    /// Matches the quota readings in the session logs, and claude-mem's requests, to each window.
    private nonisolated static func attribute(_ snapshot: UsageSnapshot, log: CodexQuotaLog) async -> [UsageWindow.ID: QuotaAttribution] {
        let now = Date.now
        let cutoff = now - (CodexAttribution.windowLengths.values.max() ?? 0)
        let readings = await log.readings(since: cutoff)
        let claudeMem = await Task.detached { ClaudeMemCodex.requests(since: cutoff) }.value

        var result: [UsageWindow.ID: QuotaAttribution] = [:]
        for window in snapshot.windows {
            guard let length = CodexAttribution.windowLengths[window.title], let resetsAt = window.resetsAt else { continue }
            let weekly = window.title == "Weekly"
            let points = readings.compactMap { reading -> (date: Date, used: Double, client: String)? in
                guard let readingReset = weekly ? reading.weeklyResetsAt : reading.sessionResetsAt,
                      abs(readingReset.timeIntervalSince(resetsAt)) < CodexAttribution.sameWindowTolerance
                else { return nil }
                return (reading.date, weekly ? reading.weekly : reading.session, reading.client)
            }
            result[window.id] = CodexAttribution.attribute(window: window, length: length, readings: points,
                                                           claudeMemRequests: claudeMem, now: now)
        }
        return result
    }

    private nonisolated static func deepSeekActivity(balance: Balance?, log: BalanceLog) async -> PrepaidActivity {
        await Task.detached {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            let week = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            let counts = ClaudeMemFiles.observationCounts(modelPrefix: "deepseek", since: [today, week])
            let readings = balance.map { log.record($0.total) } ?? log.load()
            let first = readings.first?.date
            return PrepaidActivity(observationsToday: counts[0], observationsWeek: counts[1],
                                   spentToday: BalanceLog.spent(readings, since: today),
                                   spentWeek: BalanceLog.spent(readings, since: week),
                                   trackedSince: first.flatMap { $0 > week ? $0 : nil },
                                   reference: BalanceLog.reference(readings))
        }.value
    }

    private nonisolated static func capture(_ work: () async throws -> UsageSnapshot) async -> Result<UsageSnapshot, UsageError> {
        do {
            return .success(try await work())
        } catch let error as UsageError {
            return .failure(error)
        } catch {
            return .failure(.http(0))
        }
    }
}

/// Last good snapshot per account, so an expired login still shows recent numbers.
private struct UsageCache {
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DevDock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage-cache.json")
    }()

    func load() -> [AIAccount.ID: UsageSnapshot] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([AIAccount.ID: UsageSnapshot].self, from: data)) ?? [:]
    }

    func save(_ snapshots: [AIAccount.ID: UsageSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
