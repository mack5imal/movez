import SwiftUI

/// The overlay as a snapshot: the card over the screen dim, on a placeholder desktop.
///
/// The live overlay puts an `NSVisualEffectView` behind the dim; a backdrop blur cannot be
/// rendered offscreen faithfully, so the snapshot draws the dim flat over a light placeholder,
/// exactly as the handoff screenshots do.
struct OverlaySnapshot: View {
    var state: OverlayState

    var body: some View {
        ZStack {
            Self.desktop
            Tokens.dim.color
            OverlayView(state: state, animated: false)
        }
        .frame(width: SnapshotSurface.screen.width, height: SnapshotSurface.screen.height)
        .clipped()
    }

    /// A stand-in for whatever the user was looking at.
    static var desktop: some View {
        LinearGradient(
            colors: [Color(red: 0.29, green: 0.36, blue: 0.40), Color(red: 0.17, green: 0.23, blue: 0.28)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// The strength overlay as a snapshot: the card over a flat dim on a placeholder desktop, as
/// `OverlaySnapshot` draws the movement break.
struct StrengthOverlaySnapshot: View {
    var state: StrengthOverlayState

    var body: some View {
        ZStack {
            OverlaySnapshot.desktop
            Tokens.dim.color
            StrengthOverlayView(state: state, animated: false)
        }
        .frame(width: SnapshotSurface.screen.width, height: SnapshotSurface.screen.height)
        .clipped()
    }
}
