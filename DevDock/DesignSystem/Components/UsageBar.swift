import SwiftUI

/// Thin capsule progress bar. `value` is 0...1.
struct UsageBar: View {
    var value: Double
    var tint: Color = DS.Palette.accent
    var height: CGFloat = DS.Size.bar

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.Palette.track)
                if clamped > 0 {
                    // Never narrower than a dot, so tiny values stay visible.
                    Capsule()
                        .fill(tint)
                        .frame(width: max(height * 1.6, geo.size.width * clamped))
                }
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.35), value: value)
    }

    private var clamped: Double { min(max(value, 0), 1) }

    /// Brand color normally, warning/danger as the quota runs out.
    static func tint(for value: Double, brand: Color) -> Color {
        switch value {
        case 0.9...: DS.Palette.danger
        case 0.75...: DS.Palette.warning
        default: brand
        }
    }
}
