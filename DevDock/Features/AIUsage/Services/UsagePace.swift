import Foundation

/// Where a quota window is heading at the current rate of use.
nonisolated enum UsagePace: Equatable, Sendable {
    /// Runs out before the window resets.
    case runsOut(at: Date, before: TimeInterval)
    /// Lasts until the reset, ending around this fraction.
    case onTrack(projected: Double)
}

nonisolated struct UsageSample: Codable, Sendable {
    let date: Date
    let used: Double
    let resetsAt: Date?
}

/// Usage samples per account window, kept for a week so the pace (and later a
/// history chart) can be computed. Stored next to the usage cache.
@MainActor
final class UsageHistory {
    private static let retention: TimeInterval = 8 * 86400
    /// Same reset time within this tolerance means the same window (responses drift by ~1s).
    private nonisolated static let sameWindowTolerance: TimeInterval = 10 * 60
    /// Need at least this much history in the current window before projecting.
    private nonisolated static let minimumSpan: TimeInterval = 10 * 60

    private var samples: [String: [UsageSample]]
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DevDock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("usage-history.json")
        let data = try? Data(contentsOf: url)
        samples = data.flatMap { try? JSONDecoder().decode([String: [UsageSample]].self, from: $0) } ?? [:]
    }

    func record(_ snapshot: UsageSnapshot) {
        guard let date = snapshot.updatedAt else { return }
        for window in snapshot.windows {
            let key = Self.key(snapshot.account.id, window.title)
            var list = samples[key] ?? []
            // Same reading again (throttled refresh, cached snapshot): nothing new.
            if let last = list.last, abs(last.date.timeIntervalSince(date)) < 60 { continue }
            list.append(UsageSample(date: date, used: window.used, resetsAt: window.resetsAt))
            list.removeAll { $0.date < .now - Self.retention }
            samples[key] = list
        }
        save()
    }

    func pace(accountID: AIAccount.ID, window: UsageWindow, now: Date = .now) -> UsagePace? {
        guard !window.hasReset, window.used < 1, let resetsAt = window.resetsAt else { return nil }
        return Self.pace(samples: samples[Self.key(accountID, window.title)] ?? [], window: window,
                         resetsAt: resetsAt, now: now)
    }

    /// Linear rate from the oldest recent sample in the same window to the latest reading.
    /// Session windows look back 2 h, longer windows 24 h, so the pace follows how you work now.
    nonisolated static func pace(samples: [UsageSample], window: UsageWindow, resetsAt: Date, now: Date) -> UsagePace? {
        let lookback: TimeInterval = window.title.hasPrefix("Session") ? 2 * 3600 : 86400
        let inWindow = samples.filter { sample in
            guard let reset = sample.resetsAt else { return false }
            return abs(reset.timeIntervalSince(resetsAt)) < sameWindowTolerance && sample.date >= now - lookback
        }
        guard let base = inWindow.min(by: { $0.date < $1.date }), let latest = inWindow.max(by: { $0.date < $1.date }),
              latest.date.timeIntervalSince(base.date) >= minimumSpan
        else { return nil }

        let rate = (latest.used - base.used) / latest.date.timeIntervalSince(base.date) // per second
        guard rate > 0 else { return .onTrack(projected: window.used) }

        let runsOutAt = latest.date + (1 - latest.used) / rate
        if runsOutAt < resetsAt {
            return .runsOut(at: runsOutAt, before: resetsAt.timeIntervalSince(runsOutAt))
        }
        return .onTrack(projected: min(1, window.used + rate * resetsAt.timeIntervalSince(now)))
    }

    private static func key(_ accountID: AIAccount.ID, _ window: String) -> String { "\(accountID)|\(window)" }

    private func save() {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
