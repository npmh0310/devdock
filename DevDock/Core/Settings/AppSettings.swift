import Defaults
import KeyboardShortcuts

extension Defaults.Keys {
    static let lastModule = Key<AppModule>("lastModule", default: .ports)
    /// Minutes between AI usage requests per account. The refresh button ignores it.
    static let aiUsageInterval = Key<Int>("aiUsageInterval", default: 5)
    /// Percent at which an AI quota shows in the menu bar and notifies.
    static let usageWarnPercent = Key<Int>("usageWarnPercent", default: 80)
    static let usageNotifications = Key<Bool>("usageNotifications", default: true)
    /// Launch at login is switched on once, on the first run from ~/Applications.
    static let didSetUpLoginItem = Key<Bool>("didSetUpLoginItem", default: false)
    static let menuBarStyle = Key<MenuBarStyle>("menuBarStyle", default: .rings)
    /// Account ids left out of the menu bar. Hiding rather than picking means new accounts show up by default.
    static let menuBarHiddenAccounts = Key<[String]>("menuBarHiddenAccounts", default: [])
    /// Also list ports of desktop apps and system agents.
    static let showAllPorts = Key<Bool>("showAllPorts", default: false)
}

extension KeyboardShortcuts.Name {
    /// ⌃⌥D: ⌥⌘D is taken by macOS (Dock hiding).
    static let togglePanel = Self("togglePanel", default: .init(.d, modifiers: [.control, .option]))
}
