import AppKit
import Defaults
import KeyboardShortcuts
import Observation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var panel: PanelController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests use the app as their host; keep it inert (no status item, no requests).
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }

        #if DEBUG
        if DebugSnapshot.runIfRequested(state: state) { return }
        #endif

        let panel = PanelController(state: state)
        let statusItem = StatusItemController { anchor in
            panel.toggle(anchor: anchor)
        }
        panel.onVisibilityChange = { [weak statusItem] isVisible in
            statusItem?.setHighlighted(isVisible)
        }
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak panel, weak statusItem] in
            guard let anchor = statusItem?.anchorRect else { return }
            panel?.toggle(anchor: anchor)
        }
        self.panel = panel
        self.statusItem = statusItem

        if Defaults[.usageNotifications] { Notifier.requestPermission() }
        // First run of the installed copy: start at login by default (can be turned off in Settings).
        if LoginItem.isInstalled, !Defaults[.didSetUpLoginItem] {
            LoginItem.setEnabled(true)
            Defaults[.didSetUpLoginItem] = true
        }
        observeMenuBar()
        state.startBackgroundRefresh()

        #if DEBUG
        // The status item is placed asynchronously, so wait before reading its position.
        if CommandLine.arguments.contains("--open-panel") {
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                if let anchor = statusItem.anchorRect { panel.show(anchor: anchor, takesFocus: false) }
            }
        }
        #endif
    }

    /// Mirrors `state.menuBar` into the status item, re-subscribing after each change.
    private func observeMenuBar() {
        let content = withObservationTracking {
            state.menuBar
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeMenuBar() }
        }
        statusItem?.update(image: MenuBarRenderer.image(style: content.style, items: content.items),
                           tooltip: content.tooltip)
    }
}
