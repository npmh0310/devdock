import Defaults
import Foundation
import KeyboardShortcuts

extension Defaults.Keys {
    static let lastModule = Key<AppModule>("lastModule", default: .ports)
    /// Minutes between AI usage requests per account. The refresh button ignores it.
    static let aiUsageInterval = Key<Int>("aiUsageInterval", default: 5)
    /// Percent at which an AI quota shows in the menu bar and notifies.
    static let usageWarnPercent = Key<Int>("usageWarnPercent", default: 80)
    static let usageNotifications = Key<Bool>("usageNotifications", default: true)
    /// Notify when claude-mem stops saving memories, falls behind, or recovers.
    static let claudeMemNotifications = Key<Bool>("claudeMemNotifications", default: true)
    /// Percent of a Codex window claude-mem may use before DevDock warns. 0 turns it off.
    static let claudeMemCodexLimitPercent = Key<Int>("claudeMemCodexLimitPercent", default: 50)
    /// When claude-mem runs on DeepSeek: warn once this percent of the balance is left. 0 turns it off.
    static let claudeMemDeepSeekLeftPercent = Key<Int>("claudeMemDeepSeekLeftPercent", default: 20)
    /// Launch at login is switched on once, on the first run from ~/Applications.
    static let didSetUpLoginItem = Key<Bool>("didSetUpLoginItem", default: false)
    static let menuBarStyle = Key<MenuBarStyle>("menuBarStyle", default: .rings)
    /// Account ids left out of the menu bar. Superseded by `menuBarAccounts`; read once to carry the old choice over.
    static let menuBarHiddenAccounts = Key<[String]>("menuBarHiddenAccounts", default: [])
    /// Account ids shown in the menu bar, picked in Settings. Nil until the user picks.
    static let menuBarAccounts = Key<[String]?>("menuBarAccounts")
    /// Project paths pinned to the top of Projects, in pin order.
    static let pinnedProjects = Key<[String]>("pinnedProjects", default: [])
    /// When each project was last opened from DevDock, by path.
    static let projectOpens = Key<[String: Date]>("projectOpens", default: [:])
    /// Also list ports of desktop apps and system agents.
    static let showAllPorts = Key<Bool>("showAllPorts", default: false)
}

extension KeyboardShortcuts.Name {
    /// ⌃⌥D: ⌥⌘D is taken by macOS (Dock hiding).
    static let togglePanel = Self("togglePanel", default: .init(.d, modifiers: [.control, .option]))
    /// Opens the panel on Projects with the search field focused.
    static let openProjects = Self("openProjects", default: .init(.p, modifiers: [.control, .option]))
}

/// Which accounts the menu bar shows. Until the user picks, the quota accounts they
/// had not hidden (the old setting), so updating DevDock doesn't change the menu bar.
enum MenuBarSelection {
    static func ids(accounts: [AIAccount]) -> [String] {
        if let chosen = Defaults[.menuBarAccounts] { return chosen }
        let hidden = Set(Defaults[.menuBarHiddenAccounts])
        return accounts.filter { $0.auth == .subscription && !hidden.contains($0.id) }.map(\.id)
    }
}

/// Warning thresholds as "used" fractions, 0...1.
enum UsageThresholds {
    /// Claude and Codex quotas.
    static var quota: Double { Double(Defaults[.usageWarnPercent]) / 100 }

    /// The DeepSeek balance, which only claude-mem spends: set by the "claude-mem limit" row.
    /// Off means only running out notifies.
    static var deepSeek: Double {
        let left = Defaults[.claudeMemDeepSeekLeftPercent]
        return left > 0 ? 1 - Double(left) / 100 : 1
    }

    static func warnAt(for account: AIAccount) -> Double {
        account.provider == .deepseek ? deepSeek : quota
    }
}
