import Defaults
import Foundation
import Observation

struct MenuBarContent: Equatable {
    var style: MenuBarStyle = .icon
    var items: [MenuBarUsage] = []
    var tooltip = "DevDock"
}

/// App-wide UI state. Composes feature stores and decides when they refresh.
@Observable
final class AppState {
    var module: AppModule {
        didSet { Defaults[.lastModule] = module }
    }

    let scheduler = RefreshScheduler()
    let ports = PortsStore()
    let aiUsage = AIUsageStore()

    /// What the status item shows; the AppDelegate renders it.
    private(set) var menuBar = MenuBarContent()

    @ObservationIgnored private let alertTracker = UsageAlertTracker()
    @ObservationIgnored private var backgroundLoop: Task<Void, Never>?
    @ObservationIgnored private var settingsObserver: Task<Void, Never>?

    init() {
        module = Defaults[.lastModule]
        // Ports are local and cheap: rescan on every tick. AI usage calls the network
        // and throttles itself to the "Update AI usage" setting unless forced.
        scheduler.register { [ports] _ in await ports.refresh() }
        scheduler.register { [aiUsage] force in await aiUsage.refresh(force: force) }
        aiUsage.onUpdate = { [weak self] in self?.usageDidUpdate() }
        settingsObserver = Task { [weak self] in
            for await _ in Defaults.updates([.menuBarStyle, .menuBarHiddenAccounts, .usageWarnPercent], initial: false) {
                self?.updateMenuBar()
            }
        }
    }

    /// Keeps AI usage current while the panel is closed, for the menu bar and
    /// notifications. Requests stay within the "Update AI usage every" setting.
    func startBackgroundRefresh() {
        backgroundLoop?.cancel()
        backgroundLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.aiUsage.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func panelDidOpen() {
        scheduler.start(every: .seconds(15))
    }

    func panelDidClose() {
        scheduler.stop()
    }

    // MARK: - Usage alerts

    private func usageDidUpdate() {
        let warnAt = Double(Defaults[.usageWarnPercent]) / 100
        let snapshots = aiUsage.accounts.compactMap { aiUsage.snapshots[$0.id] }
        let alerts = UsageAlerts.current(snapshots: snapshots, warnAt: warnAt)
        updateMenuBar()

        let windowKeys = Set(snapshots.flatMap { snapshot in snapshot.windows.map { "\(snapshot.account.id)|\($0.title)" } })
        let events = alertTracker.update(with: alerts, allWindowKeys: windowKeys)

        guard Defaults[.usageNotifications] else {
            Notifier.cancelPending(prefix: "reset|", keeping: [])
            return
        }
        for event in events {
            switch event {
            case .crossedWarning(let alert):
                Notifier.post(id: "warn|\(alert.key)",
                              title: "\(alert.accountTitle): \(alert.window) at \(percent(alert.used))",
                              body: resetText(alert))
            case .reachedLimit(let alert):
                Notifier.post(id: "limit|\(alert.key)",
                              title: "\(alert.accountTitle): \(alert.window) limit reached",
                              body: resetText(alert))
            }
        }
        // When a quota is used up, tell the user the moment it comes back.
        var scheduled = Set<String>()
        for alert in alerts where alert.level == .limit {
            guard let resetsAt = alert.resetsAt else { continue }
            let id = "reset|\(alert.key)"
            Notifier.schedule(id: id, at: resetsAt,
                              title: "\(alert.accountTitle): \(alert.window) has reset",
                              body: "Usage is available again.")
            scheduled.insert(id)
        }
        Notifier.cancelPending(prefix: "reset|", keeping: scheduled)
    }

    // MARK: - Menu bar

    /// Accounts with a quota, minus the ones hidden in Settings.
    func updateMenuBar() {
        let warnAt = Double(Defaults[.usageWarnPercent]) / 100
        let hidden = Set(Defaults[.menuBarHiddenAccounts])
        let shown = aiUsage.accounts
            .filter { !$0.isGateway && !hidden.contains($0.id) }
            .compactMap { account in aiUsage.snapshots[account.id].map { (account, $0) } }
            .filter { !$0.1.windows.isEmpty }

        let labels = Self.shortLabels(shown.map(\.0.name))
        let items = zip(shown, labels).map { entry, label in
            let (account, snapshot) = entry
            let windows = snapshot.windows.prefix(2).map(\.currentUsed)
            return MenuBarUsage(label: label, windows: Array(windows),
                                level: UsageLevel(used: windows.max() ?? 0, warnAt: warnAt),
                                isStale: aiUsage.errors[account.id] != nil)
        }
        let tooltip = shown.map { account, snapshot in
            let windows = snapshot.windows.map { "\($0.title) \(percent($0.currentUsed))" }.joined(separator: " · ")
            let stale = aiUsage.errors[account.id] != nil ? " (last check)" : ""
            return "\(account.title): \(windows)\(stale)"
        }.joined(separator: "\n")

        let content = MenuBarContent(style: Defaults[.menuBarStyle], items: items,
                                     tooltip: tooltip.isEmpty ? "DevDock" : tooltip)
        if content != menuBar { menuBar = content }
    }

    /// First letter of each name, two letters where first letters collide ("work", "web" → "Wo", "We").
    static func shortLabels(_ names: [String]) -> [String] {
        let first = names.map { String($0.prefix(1)).uppercased() }
        return names.enumerated().map { index, name in
            first.filter { $0 == first[index] }.count > 1 ? String(name.prefix(2)).capitalized : first[index]
        }
    }

    private func percent(_ used: Double) -> String {
        "\(Int((used * 100).rounded()))%"
    }

    private func resetText(_ alert: UsageAlert) -> String {
        guard let resetsAt = alert.resetsAt else { return "" }
        let time = resetsAt.formatted(date: .omitted, time: .shortened)
        return "Resets in \(RelativeTime.shortDuration(resetsAt.timeIntervalSinceNow)) (at \(time))."
    }
}
