import SwiftUI

nonisolated enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case claude
    case codex

    var id: Self { self }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var symbol: String {
        switch self {
        case .claude: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        }
    }

    @MainActor var brand: Color {
        switch self {
        case .claude: DS.Brand.claude
        case .codex: DS.Brand.codex
        }
    }
}

/// One login of a provider. Claude Code accounts are separate `CLAUDE_CONFIG_DIR`s,
/// e.g. `~/.claude-personal`, `~/.claude-side`, `~/.claude-work`.
nonisolated struct AIAccount: Identifiable, Hashable, Codable, Sendable {
    enum Auth: Codable, Sendable {
        /// Claude/ChatGPT subscription: has session and weekly quota.
        case subscription
        /// API key or company gateway: no quota, only token counts from local logs.
        case gateway(host: String)
    }

    /// Config directory, or the provider name when it has a single account.
    let id: String
    let provider: AIProvider
    let name: String
    let auth: Auth
    /// How to start the tool with this account, e.g. a shell alias like `claude-work`.
    var command: String?

    /// What to run in a terminal to log in again.
    var loginCommand: String {
        if let command { return command }
        switch provider {
        case .codex: return "codex"
        case .claude: return "claude"
        }
    }

    var isGateway: Bool {
        if case .gateway = auth { return true }
        return false
    }

    /// "Claude · personal", or just "Codex" for a single-account provider.
    var title: String {
        name == provider.title ? name : "\(provider.title) · \(name)"
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Where the numbers came from, shown to the user so they know how much to trust them.
nonisolated enum UsageSource: String, Codable, Sendable {
    case officialAPI
    case localLogs
    case estimated
    case mock

    var label: String {
        switch self {
        case .officialAPI: "API"
        case .localLogs: "Local logs"
        case .estimated: "Estimated"
        case .mock: "Mock"
        }
    }
}

nonisolated struct UsageWindow: Identifiable, Codable, Sendable {
    let title: String
    /// 0...1
    let used: Double
    var resetsAt: Date?
    var note: String?

    var id: String { title }

    /// The window rolled over since this was fetched.
    var hasReset: Bool { resetsAt.map { $0 <= .now } ?? false }

    /// Usage right now: a window that has reset starts again from zero.
    var currentUsed: Double { hasReset ? 0 : used }
}

/// Token count over a period, for accounts without a quota.
nonisolated struct TokenTotal: Identifiable, Codable, Sendable {
    let title: String
    let tokens: Int

    var id: String { title }
}

nonisolated struct UsageSnapshot: Codable, Sendable {
    let account: AIAccount
    var plan: String?
    var windows: [UsageWindow] = []
    var tokenTotals: [TokenTotal] = []
    /// Extra line under the windows, e.g. "Claude Code 81% · Cowork 16% of this week".
    var breakdown: String?
    var updatedAt: Date?
    var source: UsageSource

    /// The most constrained window, used for the mini bar under the account tab.
    /// Nil when the account has no quota.
    var headline: Double? { windows.map(\.currentUsed).max() }
}
