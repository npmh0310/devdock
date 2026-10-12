import SwiftUI

/// Data row (port, process, container …). Trailing actions appear on hover.
struct ListRow<Leading: View, Actions: View>: View {
    let title: String
    var subtitle: String?
    /// Always-visible tag next to the actions, e.g. a warning.
    var badge: StatusBadge?
    @ViewBuilder var leading: Leading
    @ViewBuilder var actions: Actions

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.Space.m) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DS.Typography.bodyMedium)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: DS.Space.s)
            if let badge { badge }
            HStack(spacing: DS.Space.xxs) { actions }
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(isHovered ? DS.Palette.hover : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

/// Small borderless icon button for row actions and toolbars.
struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color = .secondary
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isHovered ? tint : .secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(isHovered ? DS.Palette.hover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .clickableCursor()
        .onHover { isHovered = $0 }
        .help(help)
    }
}

/// Icon button that spins while a refresh is running.
struct RefreshButton: View {
    var isRefreshing: Bool
    let action: () -> Void

    var body: some View {
        IconButton(symbol: "arrow.clockwise", help: "Refresh", action: action)
            .symbolEffect(.rotate, options: .repeat(.continuous), isActive: isRefreshing)
            .disabled(isRefreshing)
    }
}
