import SwiftUI

/// The overlay as a snapshot: the card (or the other-display label) over the screen dim, on a
/// placeholder desktop.
///
/// The live overlay puts an `NSVisualEffectView` behind the dim; a backdrop blur cannot be
/// rendered offscreen faithfully, so the snapshot draws the dim flat over a light placeholder,
/// exactly as the handoff screenshots do.
struct OverlaySnapshot: View {
    var state: OverlayState
    var otherDisplay = false

    var body: some View {
        ZStack {
            desktop
            (state.phase == .complete ? Tokens.dimEnd : Tokens.dim).color
            if otherDisplay {
                OtherDisplayLabel(timeLeft: state.headerTrailing.replacingOccurrences(of: " LEFT", with: " left"))
            } else {
                OverlayView(state: state, animated: false)
            }
        }
        .frame(width: SnapshotSurface.screen.width, height: SnapshotSurface.screen.height)
        .clipped()
    }

    /// A stand-in for whatever the user was looking at.
    private var desktop: some View {
        LinearGradient(
            colors: [Color(red: 0.29, green: 0.36, blue: 0.40), Color(red: 0.17, green: 0.23, blue: 0.28)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
