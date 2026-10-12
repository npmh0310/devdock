import AppKit

/// Frosted backdrop for the dropdown panel: the wallpaper shows through, like a system menu.
enum GlassPanel {
    enum Material {
        case menu
        case liquidGlass
    }

    static func make(material: Material, cornerRadius: CGFloat, content: NSView) -> NSView {
        switch material {
        case .liquidGlass:
            if #available(macOS 26, *) {
                let glass = NSGlassEffectView()
                glass.cornerRadius = cornerRadius
                glass.contentView = content
                return glass
            }
            return make(material: .menu, cornerRadius: cornerRadius, content: content)

        case .menu:
            let effect = NSVisualEffectView()
            effect.material = .menu
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.maskImage = roundedMask(radius: cornerRadius)

            content.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                content.topAnchor.constraint(equalTo: effect.topAnchor),
                content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            ])
            return effect
        }
    }

    /// Stretchable rounded-rect mask; behind-window blur ignores layer corner radius.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
