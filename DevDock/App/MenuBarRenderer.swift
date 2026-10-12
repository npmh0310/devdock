import AppKit
import Defaults

nonisolated enum MenuBarStyle: String, CaseIterable, Defaults.Serializable {
    /// The DevDock mark only.
    case icon
    /// Mark plus two nested rings per account: session inside, weekly outside.
    case rings
    /// Mark plus the highest percent per account.
    case percent

    var title: String {
        switch self {
        case .icon: "Icon only"
        case .rings: "Usage rings"
        case .percent: "Percent"
        }
    }
}

/// One account as shown in the menu bar.
struct MenuBarUsage: Equatable {
    /// One or two letters, unique among shown accounts ("V", "H", "C").
    let label: String
    /// Session then weekly, 0...1.
    let windows: [Double]
    let level: UsageLevel
    /// Numbers are from an older check (login expired, offline): drawn dimmer.
    let isStale: Bool

    var highest: Double { windows.max() ?? 0 }
}

/// Draws the status item image. Monochrome like system icons; only a ring that
/// crossed the warning threshold gets color, so the menu bar stays calm.
enum MenuBarRenderer {
    private static let height: CGFloat = 18
    private static let labelFont = NSFont.systemFont(ofSize: 9, weight: .medium)
    private static let labelAlpha: CGFloat = 0.6
    private static let percentFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    private static let ringSize: CGFloat = 15
    private static let ringWidth: CGFloat = 1.6
    private static let groupGap: CGFloat = 8

    static func image(style: MenuBarStyle, items: [MenuBarUsage]) -> NSImage {
        guard style != .icon, !items.isEmpty else { return BrandMark.templateImage(pointSize: height) }

        let groups = items.map { item in (item, groupWidth(item, style: style)) }
        // The accounts themselves are the icon; the mark only shows when there is nothing else.
        let width = groups.reduce(0) { $0 + $1.1 } + groupGap * CGFloat(groups.count - 1) + 1

        // Drawn on demand so labelColor follows the menu bar's light/dark appearance.
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            var x: CGFloat = 0
            for (item, groupWidth) in groups {
                draw(item, style: style, at: x, in: rect, context: context)
                x += groupWidth + groupGap
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func groupWidth(_ item: MenuBarUsage, style: MenuBarStyle) -> CGFloat {
        let label = (item.label as NSString).size(withAttributes: [.font: labelFont]).width
        switch style {
        case .rings: return label + 3 + ringSize
        case .percent: return label + 1 + (percentText(item) as NSString).size(withAttributes: [.font: percentFont]).width
        case .icon: return 0
        }
    }

    private static func draw(_ item: MenuBarUsage, style: MenuBarStyle, at x: CGFloat, in rect: NSRect, context: CGContext) {
        let alpha: CGFloat = item.isStale ? 0.45 : 1
        let ink = NSColor.labelColor.withAlphaComponent(alpha)

        let label = NSAttributedString(string: item.label.lowercased(), attributes: [
            .font: labelFont, .foregroundColor: NSColor.labelColor.withAlphaComponent(labelAlpha * alpha),
        ])
        let labelSize = label.size()
        label.draw(at: NSPoint(x: x, y: (rect.height - labelSize.height) / 2))
        let contentX = x + labelSize.width + (style == .rings ? 3 : 1)

        switch style {
        case .rings:
            // Session is the inner ring, weekly the outer one.
            let center = CGPoint(x: contentX + ringSize / 2, y: rect.height / 2)
            let outer = ringSize / 2 - ringWidth / 2
            let radii = item.windows.count > 1 ? [outer - ringWidth - 1.2, outer] : [outer]
            for (used, radius) in zip(item.windows, radii) {
                drawRing(center: center, radius: radius, used: used,
                         color: fillColor(used: used, level: item.level, ink: ink), alpha: alpha, context: context)
            }

        case .percent:
            let text = NSAttributedString(string: percentText(item), attributes: [
                .font: percentFont,
                .foregroundColor: item.level == .limit ? NSColor.systemRed.withAlphaComponent(alpha) : ink,
            ])
            text.draw(at: NSPoint(x: contentX, y: (rect.height - text.size().height) / 2))

        case .icon:
            break
        }
    }

    private static func drawRing(center: CGPoint, radius: CGFloat, used: Double, color: NSColor,
                                 alpha: CGFloat, context: CGContext) {
        context.setLineWidth(ringWidth)
        context.setLineCap(.round)

        context.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.2 * alpha).cgColor)
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()

        let fraction = min(max(used, 0), 1)
        guard fraction > 0.005 else { return } // nothing used: no stray dot
        // Clockwise from 12 o'clock, like the system battery and Activity rings.
        let start = CGFloat.pi / 2
        context.setStrokeColor(color.cgColor)
        context.addArc(center: center, radius: radius, startAngle: start,
                       endAngle: start - .pi * 2 * fraction, clockwise: true)
        context.strokePath()
    }

    private static func fillColor(used: Double, level: UsageLevel, ink: NSColor) -> NSColor {
        guard used >= Double(Defaults[.usageWarnPercent]) / 100 else { return ink }
        return used >= 1 ? .systemRed : .systemOrange
    }

    private static func percentText(_ item: MenuBarUsage) -> String {
        "\(Int((item.highest * 100).rounded()))"
    }
}
