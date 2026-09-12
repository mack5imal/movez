import SwiftUI

/// A floating panel as a snapshot: the panel where it actually sits, over a placeholder desktop.
///
/// The panels are placed rather than centred — top-centre under the menu bar, or bottom-right
/// with its 20 pt inset — so the PNG carries the placement as well as the contents, and can be
/// held next to `screenshots/3a-panels-and-toast.png`.
struct PanelSnapshot: View {
    var viewModel: PanelViewModel
    var placement: Placement = .topCentre

    enum Placement {
        case topCentre
        case bottomRight
    }

    /// The light desktop the handoff draws its panels over.
    private static let desktop = MovezColor(hex: 0xEFED_E7)
    private static let desktopCard = MovezColor(hex: 0xF7F5_F0)

    var body: some View {
        ZStack(alignment: placement == .topCentre ? .top : .bottomTrailing) {
            desktop
            panel
        }
    }

    @ViewBuilder
    private var panel: some View {
        switch placement {
        case .topCentre:
            PanelHost(viewModel: viewModel)
                .padding(.top, PanelWindowController.topInset)
        case .bottomRight:
            AwayToastView(viewModel: viewModel)
                .padding(PanelWindowController.toastInset)
        }
    }

    /// A stand-in for whatever the user was looking at, with a window-ish card so the panel's
    /// shadow has something to fall on.
    private var desktop: some View {
        ZStack(alignment: .topLeading) {
            Self.desktop.color
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Self.desktopCard.color)
                .padding(EdgeInsets(top: 60, leading: 40, bottom: 40, trailing: 120))
        }
    }
}
