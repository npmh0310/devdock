import SwiftUI

struct SearchField: View {
    @Binding var text: String
    var prompt = "Search"

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .clickableCursor()
                .foregroundStyle(.tertiary)
            }
        }
        .font(DS.Typography.body)
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .fill(DS.Palette.hover)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .strokeBorder(isFocused ? DS.Palette.accent.opacity(0.6) : .clear, lineWidth: 1)
        )
    }
}
