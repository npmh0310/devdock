import AppKit
import SwiftUI

/// Borderless dropdown under the menu bar icon. Behaves like a menu (closes on
/// outside click, Esc, or app switch) but stays interactive, so search fields work.
final class PanelController {
    var onVisibilityChange: ((Bool) -> Void)?

    private let panel = DropdownPanel()
    private let state: AppState
    private var anchor: NSRect = .zero
    private var eventMonitors: [Any] = []
    private var appSwitchObserver: NSObjectProtocol?

    init(state: AppState) {
        self.state = state
        let root = RootView(state: state, onClose: { [weak self] in self?.close() })
        let hosting = PanelHostingView(rootView: root)
        // SwiftUI's ideal size drives the window, so the window, the glass and
        // the content always resize together.
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.onSizeChange = { [weak self] in self?.fitToContent() }
        // The panel sits right under the menu bar; don't let SwiftUI inset content for it.
        hosting.safeAreaRegions = []
        panel.contentView = GlassPanel.make(material: DS.Panel.material, cornerRadius: DS.Radius.panel, content: hosting)
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(anchor: NSRect) {
        isVisible ? close() : show(anchor: anchor)
    }

    /// `takesFocus: false` only shows the panel; used by the debug launch so
    /// screenshots never take keystrokes from the app the user is typing in.
    func show(anchor: NSRect, takesFocus: Bool = true) {
        self.anchor = anchor
        layout()
        if takesFocus {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        // Don't focus the search field on open: keystrokes meant for another app would land in it.
        panel.makeFirstResponder(nil)
        startMonitoring()
        onVisibilityChange?(true)
        state.panelDidOpen()
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        stopMonitoring()
        onVisibilityChange?(false)
        state.panelDidClose()
    }

    /// Hangs the panel below the anchor. Its height follows the content; the top edge stays put.
    private func layout() {
        let width = DS.Size.panelWidth
        let margin = DS.Space.s
        let anchorScreen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }
        // A crowded menu bar hides the icon behind the notch and moves it off-screen.
        // Then hang the panel from the top-right corner of the screen under the mouse.
        let screen = anchorScreen
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let anchorX = anchorScreen == nil ? visible.maxX : anchor.minX

        let x = min(max(anchorX, visible.minX + margin), visible.maxX - width - margin)
        panel.topLeft = NSPoint(x: x, y: min(anchor.minY, visible.maxY) - DS.Panel.gap)
        fitToContent()
    }

    private func fitToContent() {
        guard let content = panel.contentView?.subviews.first else { return }
        let size = content.fittingSize
        guard size.height > 0 else { return }
        panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: true)
    }

    private func startMonitoring() {
        stopMonitoring()
        // Clicks in other apps. Clicks on our own status item go through toggle().
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) {
            eventMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event } // Esc
            MainActor.assumeIsolated { self?.close() }
            return nil
        }) {
            eventMonitors.append(monitor)
        }
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func stopMonitoring() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
        if let appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver)
        }
        appSwitchObserver = nil
    }
}

/// Reports SwiftUI size changes (tab switch, list growing) so the panel can follow.
/// Not generic on purpose: Swift 6.3's optimizer crashes on a generic NSHostingView subclass's deinit.
private final class PanelHostingView: NSHostingView<RootView> {
    var onSizeChange: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        // Wait for SwiftUI to finish the current update before measuring.
        DispatchQueue.main.async { [weak self] in self?.onSizeChange?() }
    }
}

private final class DropdownPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: DS.Size.panelWidth, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    /// Where the panel hangs from. Every resize keeps this corner fixed,
    /// so the panel grows and shrinks downward like a menu.
    var topLeft: NSPoint?

    // Needed so text fields and the shortcut recorder receive keystrokes.
    override var canBecomeKey: Bool { true }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frame = frameRect
        if let topLeft {
            frame.origin = NSPoint(x: topLeft.x, y: topLeft.y - frame.height)
        }
        super.setFrame(frame, display: flag)
        invalidateShadow()
    }
}
