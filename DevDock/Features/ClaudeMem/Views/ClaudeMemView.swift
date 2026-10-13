import SwiftUI

/// Is claude-mem saving memories, and if not, why and what to do.
struct ClaudeMemView: View {
    let store: ClaudeMemStore

    private var s: ClaudeMemSignals { store.signals }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            SectionHeader(title: "claude-mem", subtitle: RelativeTime.updated(store.updatedAt)) {
                if let version = s.worker?.version { Text("v\(version)") }
            }

            if store.updatedAt == nil {
                EmptyState(symbol: "brain", title: "Checking…")
            } else if !s.isInstalled {
                EmptyState(symbol: "brain", title: "claude-mem not found",
                           message: "Install the claude-mem plugin in Claude Code and it shows up here.")
            } else {
                StatusCard(assessment: store.assessment)
                details
                actions
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            InfoRow(label: "Provider", value: provider, copyable: false)
            InfoRow(label: "Worker", value: worker, copyable: false)
            InfoRow(label: "Saved", value: saved, copyable: false)
            if let error = s.lastError {
                // An error from a provider it no longer uses is history, not a current problem.
                let other = error.provider.flatMap { $0 == s.provider ? nil : "on \($0.capitalized), " } ?? ""
                InfoRow(label: "Last error", value: "\(other)\(RelativeTime.moment(error.date)) · \(error.message)", lineLimit: 3)
            }
            if s.queued > 0 {
                InfoRow(label: "Queue", value: queue, copyable: false)
                    .help("Hook events waiting for the worker. Old ones are leftovers claude-mem keeps; only new ones mean it is behind.")
            }
        }
    }

    private var actions: some View {
        HStack(spacing: DS.Space.s) {
            ActionButton(title: "Log", symbol: "doc.text.magnifyingglass") { Launcher.openURL(store.logURL) }
            ActionButton(title: "Settings", symbol: "slider.horizontal.3") { Launcher.openInEditor(store.settingsPath) }
            if let viewer = store.viewerURL {
                ActionButton(title: "Viewer", symbol: "safari") { Launcher.openURL(viewer) }
            }
        }
    }

    private var provider: String {
        let name = ClaudeMemHealth.providerName(s)
        return [name, s.model].compactMap { $0 }.joined(separator: " · ")
    }

    private var worker: String {
        guard let worker = s.worker else { return "Not running" }
        guard worker.isResponding else { return "pid \(worker.pid), not responding" }
        let uptime = worker.startedAt.map { "up \(RelativeTime.shortDuration(Date.now.timeIntervalSince($0))) · " } ?? ""
        return "\(uptime)pid \(worker.pid)"
    }

    private var saved: String {
        let last = s.lastObservation.map { RelativeTime.ago($0) } ?? "never"
        return "\(last) · \(s.observationsToday) today"
    }

    private var queue: String {
        let oldest = s.oldestQueued.map { " · oldest \(RelativeTime.ago($0))" } ?? ""
        return "\(s.queued) events\(oldest)"
    }
}

private struct StatusCard: View {
    let assessment: ClaudeMemAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: DS.Space.s) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(title).font(DS.Typography.title)
            }
            Text(assessment.summary)
                .font(DS.Typography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let fix = assessment.fix {
                Label(fix, systemImage: "wrench.and.screwdriver")
                    .font(DS.Typography.caption)
                    .foregroundStyle(assessment.status == .ok ? Color.secondary : DS.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(DS.Palette.hover))
    }

    private var title: String {
        switch assessment.status {
        case .ok: "Saving memories"
        case .lagging: "Falling behind"
        case .down: "Stopped"
        }
    }

    private var color: Color {
        switch assessment.status {
        case .ok: DS.Palette.success
        case .lagging: DS.Palette.warning
        case .down: DS.Palette.danger
        }
    }
}
