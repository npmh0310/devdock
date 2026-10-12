import Defaults
import SwiftUI

struct PortsView: View {
    let store: PortsStore
    var lastRefreshed: Date?

    @State private var query = ""
    @State private var selectedID: ListeningPort.ID?
    @Default(.showAllPorts) private var showAll

    var body: some View {
        if let selectedID {
            PortDetailView(store: store, portID: selectedID) { self.selectedID = nil }
        } else {
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            SectionHeader(title: "Local Ports", subtitle: "\(shownCount) listening") {
                Text(RelativeTime.updated(lastRefreshed))
            }

            SearchField(text: $query, prompt: "Port, process or project")

            content
        }
    }

    @ViewBuilder private var content: some View {
        if let error = store.errorMessage, store.ports.isEmpty {
            EmptyState(symbol: "exclamationmark.triangle", title: "Couldn't read ports", message: error)
        } else if !store.hasLoaded {
            EmptyState(symbol: "network", title: "Scanning…")
        } else if visible.isEmpty {
            EmptyState(symbol: "network.slash",
                       title: query.isEmpty ? "Nothing is listening" : "No matches",
                       message: query.isEmpty ? "Start a dev server and it shows up here." : nil)
        } else {
            rows
        }

        if query.isEmpty, hiddenCount > 0 || showAll {
            Button(showAll ? "Hide app & system ports" : "\(hiddenCount) app & system ports hidden · Show") {
                showAll.toggle()
            }
            .buttonStyle(.plain)
            .clickableCursor()
            .font(DS.Typography.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
    }

    /// Scrolls only when the list is long, so short lists keep the panel compact.
    @ViewBuilder private var rows: some View {
        let groups = grouped
        let list = VStack(alignment: .leading, spacing: DS.Space.xxs) {
            ForEach(groups, id: \.title) { group in
                if groups.count > 1 {
                    GroupLabel(title: group.title, count: group.ports.count)
                        .padding(.top, group.title == groups.first?.title ? 0 : DS.Space.s)
                }
                ForEach(group.ports) { port in
                    PortRow(port: port, onSelect: { selectedID = port.id }, onStop: { await store.kill(port) })
                }
            }
        }
        .padding(.horizontal, -DS.Space.s)

        if visible.count > DS.Size.visibleRows {
            ScrollView { list.padding(.horizontal, DS.Space.s) }
                .padding(.horizontal, -DS.Space.s)
                .frame(height: CGFloat(DS.Size.visibleRows) * 44)
                .scrollIndicators(.automatic)
        } else {
            list
        }
    }

    // MARK: - Filtering

    private var visible: [ListeningPort] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else {
            return showAll ? store.ports : store.ports.filter { $0.category != .other }
        }
        // Searching looks at everything, hidden ports included.
        return store.ports.filter { port in
            [String(port.port), port.processName, port.project?.name, port.project?.subpath,
             port.project?.branch, port.project?.framework]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(q) }
        }
    }

    private var shownCount: Int {
        showAll ? store.ports.count : store.ports.count - hiddenCount
    }

    private var hiddenCount: Int {
        store.ports.count { $0.category == .other }
    }

    private var grouped: [(title: String, ports: [ListeningPort])] {
        let titles: [ListeningPort.Category: String] = [.project: "Projects", .service: "Services", .other: "Apps & system"]
        return Dictionary(grouping: visible, by: \.category)
            .sorted { $0.key < $1.key }
            .map { (titles[$0.key]!, $0.value) }
    }
}

private struct PortRow: View {
    let port: ListeningPort
    let onSelect: () -> Void
    let onStop: () async -> Void

    @State private var confirmingStop = false

    var body: some View {
        ListRow(title: port.displayName, subtitle: subtitle,
                badge: port.isExposed ? StatusBadge(text: "LAN", tint: DS.Palette.warning) : nil) {
            Text(verbatim: ":\(port.port)")
                .font(DS.Typography.mono)
                .foregroundStyle(DS.Palette.accent)
                .frame(width: 52, alignment: .leading)
        } actions: {
            // Databases don't speak HTTP.
            if port.category != .service {
                IconButton(symbol: "safari", help: "Open \(port.url.absoluteString)") {
                    Launcher.openURL(port.url)
                }
            }
            if port.isOwnedByCurrentUser {
                stopButton
            }
        }
        .clickableCursor()
        .onTapGesture(perform: onSelect)
        .onHover { if !$0 { confirmingStop = false } }
    }

    /// Two clicks to stop: the first arms it, the second sends SIGTERM.
    @ViewBuilder private var stopButton: some View {
        if confirmingStop {
            Button {
                confirmingStop = false
                Task { await onStop() }
            } label: {
                Text("Stop?")
                    .font(DS.Typography.badge)
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.s)
                    .frame(height: 22)
                    .background(Capsule().fill(DS.Palette.danger))
            }
            .buttonStyle(.plain)
            .clickableCursor()
            .help("Click again to stop \(port.processName) (PID \(port.pid))")
            .task {
                // Disarm if the second click doesn't come.
                try? await Task.sleep(for: .seconds(3))
                confirmingStop = false
            }
        } else {
            IconButton(symbol: "stop.circle", help: "Stop \(port.processName)", tint: DS.Palette.danger) {
                confirmingStop = true
            }
        }
    }

    /// "apps/web · Next.js · main" for projects, "node · 3493" otherwise.
    private var subtitle: String {
        guard let project = port.project else {
            return "\(port.processName) · \(port.pid)"
        }
        return [project.subpath, project.framework ?? port.processName, project.branch]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
