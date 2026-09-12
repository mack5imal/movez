import SwiftUI

/// The micro-break, in its two moments: the thirty-second count-in, and the minute itself.
///
/// The same shell as the heads-up panel and no screen dim — a micro-break is meant to be done
/// without leaving whatever is on screen behind.
struct MicroBreakView: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        PanelShell(width: Tokens.Metric.panelWidth) {
            PanelHeader(viewModel: viewModel)
            actions
        }
    }

    /// The count-in offers Start now; once the movement is running there is nothing to start.
    @ViewBuilder
    private var actions: some View {
        if viewModel.phase == .microCountIn {
            ActionRow {
                Button("Start now", action: viewModel.startNow)
                    .buttonStyle(PrimaryButtonStyle())
            } secondary: {
                snoozeButton
            } link: {
                SkipLink(viewModel: viewModel)
            }
        } else {
            ActionRow {
                EmptyView()
            } secondary: {
                snoozeButton
            } link: {
                SkipLink(viewModel: viewModel)
            }
        }
    }

    @ViewBuilder
    private var snoozeButton: some View {
        Button("Snooze 5 min", action: viewModel.snooze)
            .buttonStyle(SecondaryButtonStyle())
    }
}
