import AppKit
import SwiftUI

/// Panel layout: module tabs, current module, footer menu.
struct RootView: View {
    @Bindable var state: AppState
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, DS.Space.m)
                .padding(.top, DS.Space.m)
                .padding(.bottom, DS.Space.s)

            Hairline().padding(.horizontal, DS.Space.l)

            moduleContent
                .padding(DS.Space.l)

            Hairline().padding(.horizontal, DS.Space.l)

            footer
                .padding(.horizontal, DS.Space.l - DS.Space.s)
                .padding(.vertical, DS.Space.s)
        }
        .frame(width: DS.Size.panelWidth, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        // The window catches up with a new height one runloop later. Until then the hosting
        // view would center the content in the old height and everything jumps; pin it to the top.
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.xs) {
            ForEach(AppModule.headerModules) { module in
                TabPill(title: module.title, symbol: module.symbol, isSelected: state.module == module) {
                    state.module = module
                }
            }
            Spacer()
            RefreshButton(isRefreshing: state.scheduler.isRefreshing) {
                Task { await state.scheduler.refreshNow(force: true) }
            }
            .padding(.top, DS.Space.xs)
        }
    }

    @ViewBuilder private var moduleContent: some View {
        switch state.module {
        case .ports:
            PortsView(store: state.ports, lastRefreshed: state.scheduler.lastRefreshed)
        case .aiUsage:
            AIUsageView(store: state.aiUsage)
        case .claudeMem:
            ClaudeMemView(store: state.claudeMem)
        case .projects:
            ProjectsView(store: state.projects, focusRequest: state.projectsFocusRequest, onOpen: onClose)
        case .settings:
            SettingsView(menuBarAccounts: state.aiUsage.accounts
                .map { MenuBarAccountOption(id: $0.id, title: $0.title, name: $0.name) },
                         defaultMenuBarAccounts: MenuBarSelection.ids(accounts: state.aiUsage.accounts),
                         claudeMemOnDeepSeek: state.aiUsage.accounts.contains(DeepSeekUsageClient.account))
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            MenuRow(title: "Settings…", shortcut: "⌘,") { state.module = .settings }
                .keyboardShortcut(",", modifiers: .command)
            MenuRow(title: "Quit DevDock", shortcut: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
    }
}
