import AppKit
import SwiftUI

/// Small uppercase label above a group of rows ("PROJECTS", "SERVICES").
struct GroupLabel: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Text(title.uppercased())
            if let count { Text("\(count)").foregroundStyle(.tertiary) }
        }
        .font(DS.Typography.badge)
        .foregroundStyle(.secondary)
        .padding(.horizontal, DS.Space.s)
    }
}

/// Label/value line in a detail view. Values can be copied by clicking them.
struct InfoRow: View {
    let label: String
    let value: String
    var monospaced = false
    var lineLimit = 1
    var copyable = true

    @State private var isHovered = false
    @State private var didCopy = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
            Text(label)
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .frame(width: DS.Size.infoLabel, alignment: .leading)
            Text(value)
                .font(monospaced ? DS.Typography.monoSmall : DS.Typography.body)
                .lineLimit(lineLimit)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if copyable {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(didCopy ? AnyShapeStyle(DS.Palette.success) : AnyShapeStyle(.tertiary))
                    .opacity(isHovered || didCopy ? 1 : 0)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .clickableCursor(copyable)
        .onTapGesture {
            guard copyable else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                didCopy = false
            }
        }
        .help(copyable ? "Click to copy" : "")
    }
}

/// Compact icon + label button for detail actions (Open, VS Code, Finder …).
struct ActionButton: View {
    let title: String
    let symbol: String
    var role: ButtonRole?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(role: role, action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(height: 16)
                Text(title)
                    .font(DS.Typography.badge)
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(isHovered ? DS.Palette.hover.opacity(2) : DS.Palette.hover)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickableCursor()
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var tint: Color {
        role == .destructive ? DS.Palette.danger : .primary
    }
}

/// Centered message for empty lists and errors.
struct EmptyState: View {
    let symbol: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: DS.Space.xs) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(DS.Typography.bodyMedium)
            if let message {
                Text(message)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.l)
    }
}
