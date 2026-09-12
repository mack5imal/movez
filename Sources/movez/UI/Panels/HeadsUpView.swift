import SwiftUI

/// The minute before a break: a 64 pt disc draining beside three lines of text, and the three
/// things the user may do about it.
struct HeadsUpView: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        PanelShell(width: viewModel.panelWidth) {
            PanelHeader(viewModel: viewModel)

            if let badge = viewModel.deferredBadge {
                InfoBadge(text: badge)
            }

            ActionRow {
                Button("Start now", action: viewModel.startNow)
                    .buttonStyle(PrimaryButtonStyle())
            } secondary: {
                if viewModel.showSnooze {
                    Button("Snooze 5 min", action: viewModel.snooze)
                        .buttonStyle(SecondaryButtonStyle())
                }
            } link: {
                SkipLink(viewModel: viewModel)
            }
        }
    }
}

/// The disc-and-text row every panel opens with.
struct PanelHeader: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            TimerDisc(
                size: Tokens.Metric.panelDisc,
                progress: viewModel.progress,
                numerals: viewModel.discNumerals,
                numeralStyle: MovezType.panelDisc
            )

            VStack(alignment: .leading, spacing: 5) {
                MovezText(viewModel.eyebrow, MovezType.eyebrowPanel, color: Tokens.accent)
                MovezText(viewModel.title, MovezType.panelTitle)
                    .fixedSize(horizontal: false, vertical: true)
                MovezText(viewModel.body, MovezType.panelBody, color: Tokens.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

/// Skip is never a button — plain underlined text, inert for the first three seconds.
struct SkipLink: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        Button(viewModel.skipLabel, action: viewModel.skip)
            .buttonStyle(LinkActionStyle(disabled: !viewModel.skipEnabled))
            .disabled(!viewModel.skipEnabled)
    }
}
