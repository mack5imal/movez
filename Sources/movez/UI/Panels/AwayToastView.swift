import SwiftUI

/// "Away 7 min · break timer reset" (or "paused"), top-right, for fifteen seconds.
///
/// The countdowns are reset or paused as soon as the user comes back, and the toast is the only way
/// to undo it. That is why it is a toast and not a dialog: it is nearly always right, and the rare
/// wrong case should cost one click, not an interruption. Dismiss is the other click: what happened
/// stands and the toast goes, without waiting out its fifteen seconds.
struct AwayToastView: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        ToastShell(width: Tokens.Metric.toastWidth, remaining: viewModel.progress) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(Tokens.accent.color)
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        MovezText(viewModel.toastTitle, MovezType.toastTitle)
                            .fixedSize(horizontal: false, vertical: true)
                        MovezText(viewModel.toastSubtitle, MovezType.toastBody, color: Tokens.text2)
                    }

                    HStack(spacing: 12) {
                        Button("I was sitting", action: viewModel.reverse)
                            .buttonStyle(SecondaryButtonStyle())
                            .fixedSize()
                        Button("Dismiss", action: viewModel.dismissToast)
                            .buttonStyle(LinkActionStyle())
                            .fixedSize()
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }
}
