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


    /// Called after every refresh, also when nothing was due, so time-based state
    /// (a window passing its reset time) is re-evaluated.
    @ObservationIgnored var onUpdate: (() -> Void)?

    @ObservationIgnored private var lastAPIFetch: [AIAccount.ID: Date] = [:]
    /// The panel tick and the background loop both refresh; never let them overlap.
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private let cache = UsageCache()
    @ObservationIgnored private let history = UsageHistory()

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
        accounts = claude.map(\.account) + (hasCodex ? [CodexUsageClient.account] : [])

        let due = claude.filter { isDue($0.account.id, force: force) }

        await withTaskGroup(of: (AIAccount.ID, Result<UsageSnapshot, UsageError>).self) { group in
            for info in due {
                group.addTask {
                    switch info.account.auth {
                    case .subscription: return (info.account.id, await Self.capture { try await ClaudeUsageClient.fetch(info) })
                    case .gateway: return (info.account.id, .success(LocalLogUsage.snapshot(for: info)))
                    }
                }
            }
            if hasCodex, isDue(CodexUsageClient.account.id, force: force) {
                group.addTask { (CodexUsageClient.account.id, await Self.capture { try await CodexUsageClient.fetchLive() }) }
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
                    if id == CodexUsageClient.account.id { useCodexLogsIfNewer() }
                }
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
    private func useCodexLogsIfNewer() {
        let id = CodexUsageClient.account.id
        guard let logged = CodexUsageClient.fromSessionLogs() else { return }
        if (logged.updatedAt ?? .distantPast) > (snapshots[id]?.updatedAt ?? .distantPast) {
            snapshots[id] = logged
            history.record(logged)
        }
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
