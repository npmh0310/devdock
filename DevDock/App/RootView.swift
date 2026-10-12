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
        case .settings:
            SettingsView(menuBarAccounts: state.aiUsage.accounts
                .filter { !$0.isGateway }
                .map { MenuBarAccountOption(id: $0.id, title: $0.title) })
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
