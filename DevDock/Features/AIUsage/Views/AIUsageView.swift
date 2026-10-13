import Defaults
import SwiftUI

struct AIUsageView: View {
    let store: AIUsageStore

    @State private var selectedID: String?

    init(store: AIUsageStore, selectedID: String? = nil) {
        self.store = store
        _selectedID = State(initialValue: selectedID)
    }

    private var accounts: [AIAccount] { store.accounts }
    private var snapshots: [AIAccount.ID: UsageSnapshot] { store.snapshots }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            if accounts.isEmpty {
                EmptyState(symbol: "sparkles", title: store.hasLoaded ? "No AI accounts found" : "Loading…",
                           message: store.hasLoaded ? "Log in with Claude Code and it shows up here." : nil)
            } else {
                accountTabs
            }

            if let account = selected {
                let snapshot = snapshots[account.id]
                let error = store.errors[account.id]

                SectionHeader(title: account.title,
                              subtitle: snapshot.map { RelativeTime.updated($0.updatedAt) } ?? "No data yet") {
                    if let snapshot { StatusBadge(text: snapshot.source.label) }
                    if let plan = snapshot?.plan { Text(plan) }
                }

                if let error {
                    AccountNotice(account: account, error: error, hasOlderData: snapshot != nil)
                }

                if let snapshot {
                    // A prepaid balance draws its own window below.
                    ForEach(snapshot.balance == nil ? snapshot.windows : []) { window in
                        UsageWindowView(window: window, brand: account.provider.brand,
                                        pace: store.pace(for: account, window: window),
                                        attribution: account.provider == .codex ? store.codexAttribution[window.id] : nil)
                    }
                    if let breakdown = snapshot.breakdown {
                        Text("This week: \(breakdown)")
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    if case .gateway(let host) = account.auth {
                        GatewayUsageView(host: host, totals: snapshot.tokenTotals)
                    }
                    if let balance = snapshot.balance {
                        PrepaidUsageView(balance: balance, window: snapshot.windows.first, activity: store.deepSeekActivity)
                    }
                }
            }
        }
    }

    private var selected: AIAccount? {
        // Default to the first account that has numbers, not one with an expired login.
        accounts.first { $0.id == selectedID }
            ?? accounts.first { snapshots[$0.id] != nil && store.errors[$0.id] == nil }
            ?? accounts.first
    }

    /// One pill per account in a grid that wraps onto more rows, so every account and
    /// its usage bar is visible without scrolling sideways.
    private var accountTabs: some View {
        // Top-aligned so pills without a usage bar (gateway accounts) line up.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: DS.Space.xs, alignment: .top)],
                  alignment: .leading, spacing: DS.Space.s) {
            ForEach(accounts) { account in
                let headline = snapshots[account.id]?.headline
                TabPill(
                    title: account.name,
                    symbol: account.provider.symbol,
                    isSelected: selected == account,
                    style: .compact,
                    progress: headline,
                    progressTint: UsageBar.tint(for: headline ?? 0, brand: account.provider.brand),
                    fillsWidth: true
                ) { selectedID = account.id }
            }
        }
    }
}

private struct UsageWindowView: View {
    let window: UsageWindow
    let brand: Color
    var pace: UsagePace?
    var attribution: QuotaAttribution?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(window.title).font(DS.Typography.title)
            UsageBar(value: window.currentUsed, tint: UsageBar.tint(for: window.currentUsed, brand: brand))
            HStack {
                Text("\(Int((window.currentUsed * 100).rounded()))% used")
                Spacer()
                if window.hasReset {
                    Text("Reset, waiting for new numbers").foregroundStyle(.secondary)
                } else if let resetsAt = window.resetsAt {
                    Text("Resets in \(RelativeTime.shortDuration(resetsAt.timeIntervalSinceNow)) · \(RelativeTime.moment(resetsAt))")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(resetsAt.formatted(date: .complete, time: .shortened))
                }
            }
            .font(DS.Typography.caption)
            if let pace {
                PaceLine(pace: pace)
            }
            if let attribution, !attribution.parts.isEmpty {
                AttributionLine(attribution: attribution)
            }
            if let note = window.note, !window.hasReset {
                Text(note)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Accounts behind an API gateway have no quota, so show token counts instead of bars.
private struct GatewayUsageView: View {
    let host: String
    let totals: [TokenTotal]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            ForEach(totals) { total in
                HStack {
                    Text(total.title).font(DS.Typography.body)
                    Spacer()
                    Text("\(TokenCount.short(total.tokens)) tokens")
                        .font(DS.Typography.bodyMedium)
                        .monospacedDigit()
                }
            }
            Text("Via \(host) · no quota limit")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Why the numbers may be stale, and what to run to fix it.
private struct AccountNotice: View {
    let account: AIAccount
    let error: UsageError
    let hasOlderData: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DS.Palette.warning)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(DS.Typography.caption)
    }

    private var message: AttributedString {
        let command = account.loginCommand
        if account.auth == .prepaid { return prepaidMessage }
        switch error {
        case .tokenExpired:
            let stale = hasOlderData ? " Numbers below are from the last check." : ""
            return (try? AttributedString(markdown: "Login expired. Run `\(command)` to refresh it.\(stale)")) ?? ""
        case .noCredential:
            return (try? AttributedString(markdown: "Not logged in. Run `\(command)` and log in.")) ?? ""
        default:
            return AttributedString(error.localizedDescription)
        }
    }

    /// DeepSeek's key lives in claude-mem's config, not a login.
    private var prepaidMessage: AttributedString {
        let stale = hasOlderData ? " Numbers below are from the last check." : ""
        let text = switch error {
        case .noCredential: "No API key found. Set `OPENAI_COMPAT_API_KEY` in `~/.claude-mem/.env`."
        case .tokenExpired: "DeepSeek rejected the API key. Update it in `~/.claude-mem/.env`.\(stale)"
        default: "\(error.localizedDescription).\(stale)"
        }
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

/// Prepaid balance, what it went on, and a link to top up.
private struct PrepaidUsageView: View {
    let balance: Balance
    let window: UsageWindow?
    let activity: PrepaidActivity?

    @Default(.claudeMemDeepSeekLeftPercent) private var warnLeftPercent

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Balance").font(DS.Typography.title)
                    Text(balance.format(balance.total))
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(isLow ? DS.Palette.warning : .primary)
                }
                Spacer()
                Button("Top up") { Launcher.openURL(DeepSeekUsageClient.topUpURL) }
                    .controlSize(.small)
                    .clickableCursor()
            }
            if let window {
                UsageBar(value: window.used, tint: UsageBar.tint(for: window.used, brand: DS.Brand.deepseek))
                HStack {
                    Text("\(Int(((1 - window.used) * 100).rounded()))% left")
                    Spacer()
                    if let reference = activity?.reference {
                        Text("of \(balance.format(reference)) after last top-up").foregroundStyle(.secondary)
                    }
                }
                .font(DS.Typography.caption)
            }
            Text("Topped up \(balance.format(balance.toppedUp)) · Granted \(balance.format(balance.granted))")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)

            if !balance.isAvailable {
                Warning(text: "DeepSeek is refusing requests: top up so claude-mem can keep saving memories.")
            } else if isLow {
                Warning(text: "Under \(warnLeftPercent)% left. Top up soon, or claude-mem stops saving memories.")
            }

            if let activity {
                VStack(alignment: .leading, spacing: 0) {
                    InfoRow(label: "Spent", value: spent(activity), copyable: false)
                    InfoRow(label: "Memories",
                            value: "\(activity.observationsToday) today · \(activity.observationsWeek) in 7 days",
                            copyable: false)
                        .help("Observations claude-mem's memory observer wrote with DeepSeek.")
                }
                Text(footnote(activity))
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Usage details on platform.deepseek.com ↗") { Launcher.openURL(DeepSeekUsageClient.usageURL) }
                .buttonStyle(.plain)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.accent)
                .clickableCursor()
        }
    }

    private var isLow: Bool { warnLeftPercent > 0 && (window?.used ?? 0) >= 1 - Double(warnLeftPercent) / 100 }

    private func spent(_ activity: PrepaidActivity) -> String {
        guard let today = activity.spentToday, let week = activity.spentWeek else { return "—" }
        return "\(balance.format(today)) today · \(balance.format(week)) in 7 days"
    }

    private func footnote(_ activity: PrepaidActivity) -> String {
        let since = activity.trackedSince.map { " since \($0.formatted(date: .abbreviated, time: .shortened))" } ?? ""
        return "Spend is worked out from balance changes DevDock has seen\(since). Key and model come from ~/.claude-mem."
    }

    private struct Warning: View {
        let text: String

        var body: some View {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "Used by VS Code 62% · claude-mem 38%", in quota points. Unknown usage is what
/// nothing on this Mac accounts for: Codex cloud, another device, or a leaked login.
private struct AttributionLine: View {
    let attribution: QuotaAttribution

    var body: some View {
        let unknown = attribution.used(by: .unknown)
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
            Image(systemName: unknown > 0 ? "exclamationmark.triangle.fill" : "person.2")
                .foregroundStyle(unknown > 0 ? DS.Palette.warning : .secondary)
            Text("Used by " + attribution.parts.map { "\($0.source.title) \(Int(($0.used * 100).rounded()))%" }
                .joined(separator: " · "))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(DS.Typography.caption)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private var help: String {
        var lines = ["Matched from Codex session logs on this Mac."]
        if attribution.claudeMemRequests > 0 {
            lines.append("claude-mem made \(attribution.claudeMemRequests) Codex requests in this window; those overlapping your own sessions count as yours.")
        }
        if attribution.used(by: .unknown) > 0 {
            lines.append("Unknown: usage while nothing on this Mac was calling Codex (Codex cloud, another device, or someone else with your login).")
        }
        return lines.joined(separator: "\n")
    }
}

/// "At this pace: runs out ~12:40, 20m before reset" or "~85% by reset".
private struct PaceLine: View {
    let pace: UsagePace

    var body: some View {
        switch pace {
        case .runsOut(let at, let before):
            Label("At this pace: runs out ~\(RelativeTime.moment(at)), \(RelativeTime.shortDuration(before)) before reset",
                  systemImage: "exclamationmark.triangle.fill")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.warning)
        case .onTrack(let projected):
            Label("At this pace: ~\(Int((projected * 100).rounded()))% by reset", systemImage: "gauge.with.dots.needle.33percent")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }
}
