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
                    ForEach(snapshot.windows) { window in
                        UsageWindowView(window: window, brand: account.provider.brand,
                                        pace: store.pace(for: account, window: window))
                    }
                    if let breakdown = snapshot.breakdown {
                        Text("This week: \(breakdown)")
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    if case .gateway(let host) = account.auth {
                        GatewayUsageView(host: host, totals: snapshot.tokenTotals)
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

    /// One pill per account; scrolls sideways only when they don't fit.
    private var accountTabs: some View {
        ViewThatFits(in: .horizontal) {
            accountPills
            ScrollView(.horizontal) { accountPills }
                .scrollIndicators(.never)
        }
    }

    private var accountPills: some View {
        // Top-aligned so pills without a usage bar (gateway accounts) line up.
        HStack(alignment: .top, spacing: DS.Space.xs) {
            ForEach(accounts) { account in
                let headline = snapshots[account.id]?.headline
                TabPill(
                    title: account.name,
                    symbol: account.provider.symbol,
                    isSelected: selected == account,
                    style: .compact,
                    progress: headline,
                    progressTint: UsageBar.tint(for: headline ?? 0, brand: account.provider.brand)
                ) { selectedID = account.id }
            }
        }
    }
}

private struct UsageWindowView: View {
    let window: UsageWindow
    let brand: Color
    var pace: UsagePace?

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
