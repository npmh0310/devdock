import AppKit
import SwiftUI

extension View {
    /// Pointing-hand cursor while hovering, so clickable things read as clickable.
    ///
    /// Sets `NSCursor` on every mouse move instead of using `.pointerStyle`: the panel
    /// is non-activating, and cursor rects aren't reliable in a window of an inactive app.
    func clickableCursor(_ enabled: Bool = true) -> some View {
        onContinuousHover { phase in
            guard enabled else { return }
            switch phase {
            case .active: NSCursor.pointingHand.set()
            case .ended: NSCursor.arrow.set()
            }
        }
    }
}
