import SwiftUI

/// "Away 7 min · counted as your break", bottom-right, for six seconds.
///
/// The credit is taken as soon as the user comes back, and the toast is the only way to give it
/// back. That is why it is a toast and not a dialog: crediting the break is nearly always right,
/// and the rare wrong case should cost one click, not an interruption.
struct AwayToastView: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        ToastShell(width: Tokens.Metric.toastWidth, remaining: viewModel.progress) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Tokens.accent.color)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    MovezText(viewModel.toastTitle, MovezType.toastTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    MovezText(viewModel.toastSubtitle, MovezType.toastBody, color: Tokens.text2)
                }

                Spacer(minLength: 8)

                Button("I was sitting", action: viewModel.reverse)
                    .buttonStyle(SecondaryButtonStyle())
                    .fixedSize()
            }
        }
    }
}
