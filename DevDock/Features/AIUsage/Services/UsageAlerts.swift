import Foundation

nonisolated enum UsageLevel: Int, Comparable, Sendable {
    case normal
    /// At or above the warning threshold.
    case warning
    /// Quota used up.
    case limit

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    init(used: Double, warnAt: Double) {
        self = used >= 1 ? .limit : used >= warnAt ? .warning : .normal
    }
}

/// One quota window of one account that needs attention.
nonisolated struct UsageAlert: Sendable, Equatable {
    let accountID: AIAccount.ID
    let accountName: String
    /// "Claude · personal", for notifications.
    let accountTitle: String
    let window: String
    let used: Double
    let resetsAt: Date?
    let level: UsageLevel

    /// Identifies the window across refreshes, e.g. for scheduled notifications.
    var key: String { "\(accountID)|\(window)" }
}

/// Decides what to show in the menu bar and when to notify.
nonisolated enum UsageAlerts {
    /// Every window at or above the threshold, most urgent first.
    static func current(snapshots: [UsageSnapshot], warnAt: Double) -> [UsageAlert] {
        snapshots
            .flatMap { snapshot in
                snapshot.windows.map { window in
                    UsageAlert(accountID: snapshot.account.id, accountName: snapshot.account.name,
                               accountTitle: snapshot.account.title, window: window.title, used: window.currentUsed, resetsAt: window.resetsAt,
                               level: UsageLevel(used: window.currentUsed, warnAt: warnAt))
                }
            }
            .filter { $0.level > .normal }
            .sorted { ($0.level, $0.used) > ($1.level, $1.used) }
    }
}

/// Remembers the level each window was last notified at, so every threshold
/// fires once per quota window, also across app restarts.
@MainActor
final class UsageAlertTracker {
    nonisolated enum Event: Sendable {
        case crossedWarning(UsageAlert)
        case reachedLimit(UsageAlert)
    }

    private struct Seen: Codable {
        var level: Int
        var resetsAt: Date?
    }

    private static let storageKey = "usageAlertState"
    /// Reset times drift by a second or so between responses; anything closer is the same window.
    private static let sameWindowTolerance: TimeInterval = 10 * 60

    private var seen: [String: Seen]

    init() {
        let data = UserDefaults.standard.data(forKey: Self.storageKey)
        seen = data.flatMap { try? JSONDecoder().decode([String: Seen].self, from: $0) } ?? [:]
    }

    /// Events for windows that moved to a higher level since last time.
    /// A window seen for the first time only records a baseline, so launching
    /// the app never replays old warnings.
    func update(with alerts: [UsageAlert], allWindowKeys: Set<String>) -> [Event] {
        var events: [Event] = []
        for alert in alerts {
            let previous = seen[alert.key]
            let sameWindow = Self.isSameWindow(previous?.resetsAt, alert.resetsAt)
            let previousLevel = sameWindow ? UsageLevel(rawValue: previous?.level ?? 0) ?? .normal : .normal

            if previous != nil, alert.level > previousLevel {
                events.append(alert.level == .limit ? .reachedLimit(alert) : .crossedWarning(alert))
            }
            seen[alert.key] = Seen(level: alert.level.rawValue, resetsAt: alert.resetsAt)
        }
        // Windows back under the threshold start over, so the next crossing notifies again.
        for key in allWindowKeys where !alerts.contains(where: { $0.key == key }) {
            seen[key] = Seen(level: UsageLevel.normal.rawValue, resetsAt: seen[key]?.resetsAt)
        }
        save()
        return events
    }

    private static func isSameWindow(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.timeIntervalSince(b)) < sameWindowTolerance
    }

    private func save() {
        if let data = try? JSONEncoder().encode(seen) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
