import AppKit

/// The DevDock mark: a dock tray with three rising bars, part dev dock, part usage meter.
/// Drawn from vector paths so the menu bar glyph and the app icon stay identical.
enum BrandMark {
    /// Paths in a unit square, y up. The last bar is the accent in the app icon.
    static func paths(in rect: CGRect) -> (tray: CGPath, bars: [CGPath]) {
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat) -> CGPath {
            let frame = CGRect(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height,
                               width: w * rect.width, height: h * rect.height)
            let corner = radius * min(rect.width, rect.height)
            return CGPath(roundedRect: frame, cornerWidth: corner, cornerHeight: corner, transform: nil)
        }
        let tray = r(0.08, 0.08, 0.84, 0.14, radius: 0.07)
        let bars = [
            r(0.17, 0.28, 0.17, 0.26, radius: 0.06),
            r(0.415, 0.28, 0.17, 0.42, radius: 0.06),
            r(0.66, 0.28, 0.17, 0.58, radius: 0.06),
        ]
        return (tray, bars)
    }

    /// Monochrome glyph for the menu bar; macOS tints it for light/dark menu bars.
    static func templateImage(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let (tray, bars) = paths(in: rect.insetBy(dx: 1, dy: 1))
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(tray)
            bars.forEach(context.addPath)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "DevDock"
        return image
    }

    /// Full-color app icon artwork, following the macOS icon grid (824/1024 body).
    static func drawAppIcon(in context: CGContext, size: CGFloat) {
        let body = CGRect(x: size * 100 / 1024, y: size * 100 / 1024, width: size * 824 / 1024, height: size * 824 / 1024)
        let corner = size * 185 / 1024
        let squircle = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!

        // Drop shadow.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -size * 10 / 1024), blur: size * 28 / 1024,
                          color: CGColor(gray: 0, alpha: 0.35))
        context.addPath(squircle)
        context.setFillColor(CGColor(red: 0.16, green: 0.12, blue: 0.42, alpha: 1))
        context.fillPath()
        context.restoreGState()

        // Indigo → violet body.
        context.saveGState()
        context.addPath(squircle)
        context.clip()
        let bodyGradient = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 0.43, green: 0.34, blue: 0.97, alpha: 1),
            CGColor(red: 0.16, green: 0.12, blue: 0.45, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(bodyGradient, start: CGPoint(x: body.midX, y: body.maxY),
                                   end: CGPoint(x: body.midX, y: body.minY), options: [])
        // Soft glass highlight on the upper half.
        let shine = CGGradient(colorsSpace: space, colors: [
            CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0),
        ] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(shine, start: CGPoint(x: body.midX, y: body.maxY),
                                   end: CGPoint(x: body.midX, y: body.midY), options: [])
        context.restoreGState()

        // Hairline edge.
        context.addPath(squircle)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.16))
        context.setLineWidth(size * 3 / 1024)
        context.strokePath()

        // The mark, white with a coral accent bar.
        let markSize = size * 0.5
        let markRect = CGRect(x: (size - markSize) / 2, y: (size - markSize) / 2 - size * 0.01,
                              width: markSize, height: markSize)
        let (tray, bars) = paths(in: markRect)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -size * 4 / 1024), blur: size * 12 / 1024,
                          color: CGColor(gray: 0, alpha: 0.25))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.addPath(tray)
        bars.dropLast().forEach(context.addPath)
        context.fillPath()
        context.setFillColor(CGColor(red: 1.0, green: 0.55, blue: 0.40, alpha: 1))
        context.addPath(bars.last!)
        context.fillPath()
        context.restoreGState()
    }
}
