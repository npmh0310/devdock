import Defaults
import SwiftUI

/// Type a few letters, Enter: a new iTerm tab in that project. ⌘1–9 opens the first nine
/// without typing, ⌘P pins the selected one.
struct ProjectsView: View {
    let store: ProjectsStore
    /// Bumped by the ⌃⌥P shortcut so the search field takes focus even if the view was already open.
    var focusRequest = 0
    var onOpen: () -> Void = {}

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool
    @Default(.pinnedProjects) private var pinned

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            SectionHeader(title: "Projects", subtitle: "\(store.projects.count) in ~/workspace") {
                Text("⌘1–9 open · ⌘P pin")
            }
            searchField
            content
        }
        .onAppear { searchFocused = true }
        .onChange(of: focusRequest) { searchFocused = true }
        .onChange(of: query) { selection = 0 }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Project name", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { open(at: selection) }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(phases: .down) { press in
                    guard press.modifiers == .command else { return .ignored }
                    if let digit = Int(press.characters), (1...9).contains(digit) {
                        open(at: digit - 1)
                        return .handled
                    }
                    if press.characters == "p", visible.indices.contains(selection) {
                        store.togglePin(visible[selection])
                        return .handled
                    }
                    return .ignored
                }
        }
        .font(DS.Typography.body)
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(DS.Palette.hover))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .strokeBorder(searchFocused ? DS.Palette.accent.opacity(0.6) : .clear, lineWidth: 1)
        )
    }

    @ViewBuilder private var content: some View {
        if !store.hasLoaded {
            EmptyState(symbol: "folder", title: "Scanning…")
        } else if store.projects.isEmpty {
            EmptyState(symbol: "folder.badge.questionmark", title: "No projects",
                       message: "Folders in ~/workspace/<group>/ show up here.")
        } else if visible.isEmpty {
            EmptyState(symbol: "magnifyingglass", title: "No matches")
        } else {
            list
        }
    }

    private var list: some View {
        let rows = visible
        let list = VStack(alignment: .leading, spacing: DS.Space.xxs) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, project in
                if query.isEmpty, let title = sectionTitle(at: index, in: rows) {
                    GroupLabel(title: title)
                        .padding(.top, index == 0 ? 0 : DS.Space.s)
                }
                ProjectRow(project: project, shortcut: index < 9 ? index + 1 : nil,
                           isSelected: index == selection, isPinned: pinned.contains(project.id),
                           onOpen: { open(at: index) }, onPin: { store.togglePin(project) })
                    .id(project.id)
            }
        }
        .padding(.horizontal, -DS.Space.s)

        return ScrollViewReader { proxy in
            Group {
                if rows.count > DS.Size.visibleRows {
                    ScrollView { list.padding(.horizontal, DS.Space.s) }
                        .padding(.horizontal, -DS.Space.s)
                        .frame(height: CGFloat(DS.Size.visibleRows) * 40)
                } else {
                    list
                }
            }
            .onChange(of: selection) {
                guard rows.indices.contains(selection) else { return }
                proxy.scrollTo(rows[selection].id)
            }
        }
    }

    // MARK: - Data

    private var visible: [Project] {
        let ordered = ProjectRanking.sorted(store.projects, pinned: pinned)
        return ProjectRanking.search(ordered, query: query)
    }

    /// "Pinned", "Recent", then the group of each remaining project.
    private func sectionTitle(at index: Int, in rows: [Project]) -> String? {
        func title(_ project: Project) -> String {
            if pinned.contains(project.id) { return "Pinned" }
            if let date = project.lastActivity, date > .now - 14 * 86400 { return "Recent" }
            return "Older"
        }
        let current = title(rows[index])
        return index == 0 || title(rows[index - 1]) != current ? current : nil
    }

    private func move(_ step: Int) -> KeyPress.Result {
        selection = min(max(selection + step, 0), max(visible.count - 1, 0))
        return .handled
    }

    private func open(at index: Int) {
        let rows = visible
        guard rows.indices.contains(index) else { return }
        store.open(rows[index])
        query = ""
        onOpen()
    }
}

private struct ProjectRow: View {
    let project: Project
    let shortcut: Int?
    let isSelected: Bool
    let isPinned: Bool
    let onOpen: () -> Void
    let onPin: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: isPinned ? "pin.fill" : "folder")
                .font(.system(size: 12))
                .foregroundStyle(isPinned ? DS.Palette.accent : .secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name).font(DS.Typography.bodyMedium).lineLimit(1)
                Text(subtitle).font(DS.Typography.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: DS.Space.s)
            if isHovered {
                IconButton(symbol: isPinned ? "pin.slash" : "pin", help: isPinned ? "Unpin" : "Pin to top", action: onPin)
                IconButton(symbol: "folder", help: "Show in Finder") { Launcher.revealInFinder(project.path) }
            } else if let shortcut {
                Text("⌘\(shortcut)")
                    .font(DS.Typography.monoSmall)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(isSelected ? DS.Palette.accent.opacity(0.18) : isHovered ? DS.Palette.hover : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onOpen)
        .clickableCursor()
        .help(project.path)
    }

    /// "madison · 2m ago", "start-up/tium-power · 3d ago".
    private var subtitle: String {
        let place = [project.group, project.parent].compactMap { $0 }.joined(separator: "/")
        guard let date = project.lastActivity else { return place }
        return "\(place) · \(RelativeTime.ago(date))"
    }
}
