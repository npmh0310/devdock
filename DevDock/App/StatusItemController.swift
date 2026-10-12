import AppKit

/// The DevDock icon in the menu bar.
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let onClick: (NSRect) -> Void

    init(onClick: @escaping (NSRect) -> Void) {
        self.onClick = onClick
        super.init()
        // Keeps the position after the user ⌘-drags the icon.
        item.autosaveName = "DevDockStatusItem"

        guard let button = item.button else { return }
        button.image = BrandMark.templateImage()
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    /// Screen rect of the menu bar button; the panel hangs below it.
    var anchorRect: NSRect? {
        guard let button = item.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    func update(image: NSImage, tooltip: String) {
        guard let button = item.button else { return }
        button.image = image
        button.toolTip = tooltip
    }

    func setHighlighted(_ highlighted: Bool) {
        item.button?.highlight(highlighted)
    }

    @objc private func clicked() {
        if let anchorRect { onClick(anchorRect) }
    }
}
