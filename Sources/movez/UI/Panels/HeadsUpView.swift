import SwiftUI

// design: headsup
// design: strength-headsup

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
///
/// The eyebrow is the mode badge, so every panel names its mode by glyph and word. A running
/// strength micro-break adds its dose under the move's name, in accent like the overlay's.
struct PanelHeader: View {
    @ObservedObject var viewModel: PanelViewModel

    /// The dose line's look, which the tests hold to the design's `panel-dose`.
    static let doseStyle = MovezType.panelDose
    static let doseColor = Tokens.accent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            TimerDisc(
                size: Tokens.Metric.panelDisc,
                progress: viewModel.discProgress,
                numerals: viewModel.discNumerals,
                mode: viewModel.discMode,
                numeralStyle: MovezType.panelDisc
            )

            VStack(alignment: .leading, spacing: 5) {
                if let label = viewModel.eyebrowLabel {
                    ModeBadge(definition: viewModel.modeDefinition, size: .panel, label: label)
                }
                MovezText(viewModel.title, MovezType.panelTitle)
                    .fixedSize(horizontal: false, vertical: true)
                if let dose = viewModel.microDose {
                    MovezText(dose.line, Self.doseStyle, color: Self.doseColor)
                        .fixedSize(horizontal: false, vertical: true)
                    if let modifier = dose.modifier {
                        MovezText(modifier, MovezType.panelBody, color: Tokens.text, lineLimit: 1)
                    }
                }
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
