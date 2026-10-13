import SwiftUI

/// Icon tab, filled with the accent color when selected, with an optional mini usage bar below.
struct TabPill: View {
    enum Style {
        /// Icon above label, fixed width. Used for the module header.
        case regular
        /// Icon beside label. Used for context tabs inside a module.
        case compact
    }

    let title: String
    let symbol: String
    var isSelected: Bool
    var style: Style = .regular
    var progress: Double?
    var progressTint: Color = DS.Palette.success
    /// Fill the width it is given, e.g. a grid cell, instead of hugging the label.
    var fillsWidth = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.xs) {
                label
                    // Only colors animate: animating layout made the label slide when the panel resized.
                    .animation(.snappy(duration: 0.18)) {
                        $0.foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    }
                    .frame(width: style == .regular ? DS.Size.tabWidth : nil)
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
                    .padding(.horizontal, style == .compact ? (fillsWidth ? DS.Space.xs : DS.Space.s + 2) : 0)
                    .padding(.vertical, style == .regular ? 5 : 4)
                    .animation(.easeOut(duration: 0.12)) { content in
                        content.background {
                            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                .fill(background)
                                .shadow(color: isSelected ? DS.Palette.accent.opacity(0.35) : .clear, radius: 4, y: 1)
                        }
                    }

                if let progress {
                    UsageBar(value: progress, tint: progressTint, height: DS.Size.miniBar)
                        .padding(.horizontal, DS.Space.xs)
                }
            }
            .fixedSize(horizontal: style == .compact && !fillsWidth, vertical: false)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickableCursor()
        .onHover { isHovered = $0 }
        .help(title)
    }

    @ViewBuilder private var label: some View {
        switch style {
        case .regular:
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(height: 18) // symbols differ in height; keep labels aligned
                Text(title).font(DS.Typography.tab)
            }
        case .compact:
            HStack(spacing: DS.Space.xs) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).font(DS.Typography.tab).lineLimit(1).minimumScaleFactor(0.85)
            }
        }
    }

    private var background: Color {
        if isSelected { return DS.Palette.accent }
        return isHovered ? DS.Palette.hover : .clear
    }
}
