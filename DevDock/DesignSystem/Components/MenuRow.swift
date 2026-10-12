import SwiftUI

/// A row that looks and behaves like a system menu item: accent highlight on hover.
struct MenuRow: View {
    let title: String
    var symbol: String?
    var shortcut: String?
    var showsChevron = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s) {
                if let symbol {
                    Image(systemName: symbol)
                        .frame(width: DS.Size.icon)
                }
                Text(title)
                Spacer(minLength: DS.Space.s)
                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(isHovered ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.tertiary))
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .font(DS.Typography.body)
            .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                    .fill(isHovered ? DS.Palette.accent : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickableCursor()
        .onHover { isHovered = $0 }
    }
}
