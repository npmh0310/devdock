import SwiftUI

/// Bold title, secondary subtitle, and an optional trailing accessory ("Updated just now · Max").
struct SectionHeader<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(title).font(DS.Typography.title)
            HStack(spacing: DS.Space.s) {
                if let subtitle {
                    Text(subtitle)
                }
                Spacer(minLength: 0)
                accessory
            }
            .font(DS.Typography.caption)
            .foregroundStyle(.secondary)
        }
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Inset hairline between panel sections.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(DS.Palette.divider)
            .frame(height: 1)
    }
}
