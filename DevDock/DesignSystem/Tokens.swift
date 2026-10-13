import SwiftUI

/// Design tokens. Feature views use these instead of hard-coded values,
/// so the whole look can be tuned from this file.
enum DS {
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
    }

    enum Radius {
        static let panel: CGFloat = 18
        static let control: CGFloat = 10
        static let row: CGFloat = 7
    }

    enum Size {
        static let panelWidth: CGFloat = 320
        static let bar: CGFloat = 6
        static let miniBar: CGFloat = 3
        static let tabWidth: CGFloat = 58
        static let icon: CGFloat = 16
        /// Label column in detail views.
        static let infoLabel: CGFloat = 64
        /// Rows shown before a list starts scrolling.
        static let visibleRows = 10
    }

    enum Panel {
        /// Backdrop of the dropdown. `.menu` matches the system menu look; `.liquidGlass` is clearer.
        static let material: GlassPanel.Material = .menu
        /// Gap between the menu bar and the top of the panel.
        static let gap: CGFloat = 6
    }

    enum Palette {
        static let accent = Color.accentColor
        static let track = Color.primary.opacity(0.10)
        static let divider = Color.primary.opacity(0.12)
        static let hover = Color.primary.opacity(0.07)
        static let border = Color.white.opacity(0.25)
        static let success = Color(red: 0.30, green: 0.70, blue: 0.56)
        static let warning = Color(red: 0.93, green: 0.62, blue: 0.20)
        static let danger = Color(red: 0.90, green: 0.33, blue: 0.30)
    }

    enum Brand {
        static let claude = Color(red: 0.78, green: 0.47, blue: 0.34)
        static let codex = Color(red: 0.29, green: 0.66, blue: 0.58)
        static let deepseek = Color(red: 0.30, green: 0.42, blue: 1.0)
    }

    enum Typography {
        static let title = Font.system(size: 14, weight: .semibold)
        static let body = Font.system(size: 13)
        static let bodyMedium = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 11.5)
        static let tab = Font.system(size: 11, weight: .medium)
        static let badge = Font.system(size: 10, weight: .semibold)
        static let mono = Font.system(size: 12.5, weight: .semibold, design: .monospaced)
        static let monoSmall = Font.system(size: 11.5, design: .monospaced)
        static let display = Font.system(size: 20, weight: .bold, design: .monospaced)
    }
}
