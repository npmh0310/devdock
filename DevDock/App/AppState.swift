import Defaults
import Foundation
import Observation

struct MenuBarContent: Equatable {
    var style: MenuBarStyle = .icon
    var items: [MenuBarUsage] = []
    var tooltip = "DevDock"
    /// Something needs attention outside the quotas (claude-mem stopped): a red dot.
    var alert = false
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
    let claudeMem = ClaudeMemStore()
    let projects = ProjectsStore()
    /// Bumped by ⌃⌥P so Projects focuses its search field.
    var projectsFocusRequest = 0

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
        scheduler.register { [claudeMem] _ in await claudeMem.refresh() }
        scheduler.register { [projects] _ in await projects.refresh() }
        aiUsage.onUpdate = { [weak self] in self?.usageDidUpdate() }
        claudeMem.onUpdate = { [weak self] in self?.claudeMemDidUpdate() }
        // DeepSeek only shows up while claude-mem runs on it, so its balance is claude-mem's.
        claudeMem.outOfCredit = { [aiUsage] in
            aiUsage.snapshots[DeepSeekUsageClient.account.id]?.balance.map { !$0.isAvailable } ?? false
        }
        settingsObserver = Task { [weak self] in
            for await _ in Defaults.updates([.menuBarStyle, .menuBarAccounts, .usageWarnPercent, .claudeMemDeepSeekLeftPercent], initial: false) {
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
                await self?.claudeMem.refresh()
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
        let snapshots = aiUsage.accounts.compactMap { aiUsage.snapshots[$0.id] }
        let alerts = UsageAlerts.current(snapshots: snapshots, warnAt: UsageThresholds.warnAt(for:))
        updateMenuBar()

        let windowKeys = Set(snapshots.flatMap { snapshot in snapshot.windows.map { "\(snapshot.account.id)|\($0.title)" } })
        let events = alertTracker.update(with: alerts, allWindowKeys: windowKeys)

        guard Defaults[.usageNotifications] else {
            Notifier.cancelPending(prefix: "reset|", keeping: [])
            return
        }
        for event in events {
            switch event {
            case .crossedWarning(let alert) where alert.accountID == DeepSeekUsageClient.account.id:
                Notifier.post(id: "warn|\(alert.key)",
                              title: "DeepSeek: \(percent(1 - alert.used)) of balance left\(deepSeekBalanceText)",
                              body: "claude-mem's memory observer runs on it. Top up at platform.deepseek.com.")
            case .reachedLimit(let alert) where alert.accountID == DeepSeekUsageClient.account.id:
                Notifier.post(id: "limit|\(alert.key)",
                              title: "DeepSeek balance used up",
                              body: "claude-mem can't save memories until you top up at platform.deepseek.com.")
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
        warnAboutClaudeMem()
    }

    /// " ($0.39)", the DeepSeek balance for notification titles.
    private var deepSeekBalanceText: String {
        aiUsage.snapshots[DeepSeekUsageClient.account.id]?.balance.map { " (\($0.format($0.total)))" } ?? ""
    }

    /// claude-mem's observer runs on the Codex login in the background and can eat a
    /// whole session window on its own. Warn once per window when it passes the limit.
    private func warnAboutClaudeMem() {
        let limit = Double(Defaults[.claudeMemCodexLimitPercent]) / 100
        guard limit > 0, let snapshot = aiUsage.snapshots[CodexUsageClient.account.id] else { return }
        var warned = UserDefaults.standard.dictionary(forKey: Self.claudeMemWarnedKey) as? [String: Double] ?? [:]
        for window in snapshot.windows {
            guard let resetsAt = window.resetsAt, let attribution = aiUsage.codexAttribution[window.id] else { continue }
            let used = attribution.used(by: .claudeMem)
            guard used >= limit else { continue }
            // Reset times drift a little between responses; anything close is the same window.
            if let last = warned[window.title], abs(last - resetsAt.timeIntervalSince1970) < 600 { continue }
            warned[window.title] = resetsAt.timeIntervalSince1970
            let model = (ClaudeMemFiles.settings()["CLAUDE_MEM_CODEX_MODEL"] as? String).map { " (\($0))" } ?? ""
            Notifier.post(id: "claudemem|\(window.title)",
                          title: "claude-mem used \(percent(used)) of Codex \(window.title.lowercased())",
                          body: "Its memory observer\(model) runs on your Codex login in the background. Switch its provider in ~/.claude-mem/settings.json to stop it.")
        }
        UserDefaults.standard.set(warned, forKey: Self.claudeMemWarnedKey)
    }

    private static let claudeMemWarnedKey = "claudeMemWarnedWindows"

    // MARK: - claude-mem

    /// Notifies once per change: stopped, falling behind (only from ok), and back to saving.
    private func claudeMemDidUpdate() {
        updateMenuBar()
        let assessment = claudeMem.assessment
        guard claudeMem.isInstalled else { return }
        let defaults = UserDefaults.standard
        let previous = ClaudeMemAssessment.Status(rawValue: defaults.integer(forKey: Self.claudeMemStatusKey)) ?? .ok
        defaults.set(assessment.status.rawValue, forKey: Self.claudeMemStatusKey)
        guard Defaults[.claudeMemNotifications], assessment.status != previous else { return }

        let body = [assessment.summary, assessment.fix].compactMap { $0 }.joined(separator: "\n")
        switch assessment.status {
        case .down:
            Notifier.post(id: "claudemem|status", title: "claude-mem stopped saving memories", body: body)
        case .lagging where previous == .ok:
            Notifier.post(id: "claudemem|status", title: "claude-mem is falling behind", body: body)
        case .ok:
            Notifier.post(id: "claudemem|status", title: "claude-mem is saving memories again", body: assessment.summary)
        case .lagging:
            break // Recovering from stopped: no news yet.
        }
    }

    private static let claudeMemStatusKey = "claudeMemLastStatus"

    // MARK: - Menu bar

    /// The accounts picked in Settings: quota rings or percent, today's tokens for a
    /// gateway, the balance for a prepaid key.
    func updateMenuBar() {
        let selected = Set(MenuBarSelection.ids(accounts: aiUsage.accounts))
        let shown = aiUsage.accounts
            .filter { selected.contains($0.id) }
            .compactMap { account in aiUsage.snapshots[account.id].map { (account, $0) } }
            .filter { !$0.1.windows.isEmpty || $0.1.balance != nil || !$0.1.tokenTotals.isEmpty }

        let labels = Self.shortLabels(shown.map(\.0.name))
        let items = zip(shown, labels).map { entry, label in
            let (account, snapshot) = entry
            let isStale = aiUsage.errors[account.id] != nil
            if let balance = snapshot.balance {
                return MenuBarUsage(label: label, windows: [],
                                    level: UsageLevel(used: snapshot.headline ?? 0, warnAt: UsageThresholds.warnAt(for: account)),
                                    isStale: isStale,
                                    text: balance.format(balance.total))
            }
            if snapshot.windows.isEmpty, let today = snapshot.tokenTotals.first {
                return MenuBarUsage(label: label, windows: [], level: .normal, isStale: isStale,
                                    text: TokenCount.short(today.tokens))
            }
            let windows = snapshot.windows.prefix(2).map(\.currentUsed)
            return MenuBarUsage(label: label, windows: Array(windows),
                                level: UsageLevel(used: windows.max() ?? 0, warnAt: UsageThresholds.warnAt(for: account)),
                                isStale: isStale)
        }
        let tooltip = shown.map { account, snapshot in
            let value = if let balance = snapshot.balance {
                "Balance \(balance.format(balance.total))"
            } else if snapshot.windows.isEmpty, let today = snapshot.tokenTotals.first {
                "\(TokenCount.short(today.tokens)) tokens today"
            } else {
                snapshot.windows.map { "\($0.title) \(percent($0.currentUsed))" }.joined(separator: " · ")
            }
            let stale = aiUsage.errors[account.id] != nil ? " (last check)" : ""
            return "\(account.title): \(value)\(stale)"
        }.joined(separator: "\n")

        let memoryDown = claudeMem.isInstalled && claudeMem.assessment.status == .down
        let memoryLine = memoryDown ? "claude-mem stopped: \(claudeMem.assessment.summary)" : nil
        let lines = [tooltip.isEmpty ? nil : tooltip, memoryLine].compactMap { $0 }
        let content = MenuBarContent(style: Defaults[.menuBarStyle], items: items,
                                     tooltip: lines.isEmpty ? "DevDock" : lines.joined(separator: "\n"),
                                     alert: memoryDown)
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
