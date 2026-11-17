import SwiftUI

// design: strength-set
// design: endrange-break

/// A strength or end-range break in the overlay: the movement break's frame (card, disc, strip,
/// action row) around a body that shows the set, the rest, or the move.
///
/// The disc is Done, so the action row never swaps Snooze for a Done button, and there is no end
/// screen: when the session closes the card fades and the overlay goes.
struct StrengthOverlayView: View {
    var state: StrengthOverlayState
    var actions = StrengthOverlayActions()
    var animated = true
    /// The meter's reading this frame, when the live overlay animates it between ticks; nil uses
    /// the state's own, which is what snapshots and Reduce Motion want.
    var livePacer: RepPacerState?

    /// The width of a centred body, from the handoff.
    private static let centredWidth: CGFloat = 780
    /// The text column beside the meter: 180 + 56 + 604 is the card's 840 pt of content.
    private static let textColumn: CGFloat = 604
    private static let columnGap: CGFloat = 56
    /// A name longer than this drops from 80 pt to 56 pt in a centred body.
    private static let longNameCharacters = 16

    /// The card is drawn while the session runs; once it closes it fades ahead of the dim.
    var showsCard: Bool { !state.isClosed }

    var body: some View {
        OverlayCard(disc: disc) {
            VStack(spacing: 0) {
                OverlayHeader(mode: state.mode, trailing: state.headerTrailing)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
                bodyContent
                    .id(bodyIdentity)
                    .transition(animated && !state.reduceMotion ? .opacity : .identity)
                Spacer(minLength: 0)
                SequenceStrip(items: state.strip, truncatesNames: true)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 28)
                actionRow
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22)
            }
            .padding(OverlayCardLayout.contentInsets)
        }
    }

    /// The disc the card hangs from; not private so a test can read what VoiceOver says for Done.
    var disc: TimerDisc? {
        guard showsCard else { return nil }
        return TimerDisc(
            size: Tokens.Metric.overlayDisc,
            progress: state.discProgress,
            numerals: state.discNumerals,
            label: state.discLabel,
            mode: state.discMode,
            action: actions.disc
        )
    }

    /// A new segment crossfades its body; a tick inside one does not.
    private var bodyIdentity: String {
        "\(String(describing: state.segment))|\(state.movementName)"
    }

    @ViewBuilder
    private var bodyContent: some View {
        if state.isRest {
            restBody
        } else if state.showsMeter, let pacer = livePacer ?? state.pacer {
            meterBody(pacer)
        } else {
            centredBody
        }
    }

    // MARK: - Rep-counted set

    /// The meter column beside a left-aligned text column.
    private func meterBody(_ pacer: RepPacerState) -> some View {
        HStack(alignment: .center, spacing: Self.columnGap) {
            RepMeter(state: pacer, reduceMotion: state.reduceMotion)
            VStack(alignment: .leading, spacing: 0) {
                MovezText(state.kicker, MovezType.setKicker, color: Tokens.text2, lineLimit: 1)
                MovezText(state.movementName, MovezType.setName, color: Tokens.text, lineLimit: 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                HStack(alignment: .center, spacing: 16) {
                    MovezText(state.dose, MovezType.dose, color: Tokens.text, lineLimit: 1)
                    Spacer(minLength: 0)
                    if state.isSideBlock {
                        SideToggle(side: state.side, compact: true, choose: { _ in })
                            // The timeline changes sides on its own clock; the pill only shows it.
                            .allowsHitTesting(false)
                    }
                }
                .padding(.top, 5)
                if let modifier = state.doseModifier {
                    MovezText(modifier, MovezType.doseModifier, color: Tokens.text2, lineLimit: 1)
                        .padding(.top, 6)
                }
                instruction(MovezType.instructionSide, alignment: .leading)
                    .padding(.top, state.doseModifier != nil || state.isSideBlock ? 18 : 22)
            }
            .frame(width: Self.textColumn, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Centred bodies

    /// The warm-up, a hold set, the cool-down, a lead-in before the warm-up, and every end-range
    /// block: one centred column with no meter.
    private var centredBody: some View {
        VStack(spacing: 0) {
            if !state.kicker.isEmpty {
                MovezText(state.kicker, MovezType.setKicker, color: Tokens.text2, alignment: .center, lineLimit: 1)
                    .padding(.bottom, 8)
            }
            MovezText(state.movementName, nameStyle, color: Tokens.text, alignment: .center, lineLimit: 2)
                .fixedSize(horizontal: false, vertical: true)
            if !state.dose.isEmpty {
                MovezText(state.dose, MovezType.dose, color: Tokens.text, alignment: .center, lineLimit: 1)
                    .padding(.top, 6)
            }
            if let modifier = state.doseModifier {
                MovezText(modifier, MovezType.doseModifier, color: Tokens.text2, alignment: .center, lineLimit: 1)
                    .padding(.top, 6)
            }
            if state.isSideBlock {
                SideToggle(side: state.side, choose: { _ in })
                    .allowsHitTesting(false)
                    .padding(.top, 18)
            }
            instruction(instructionStyle, alignment: .center)
                .padding(.top, state.isSideBlock ? 18 : 22)
        }
        .frame(maxWidth: Self.centredWidth)
        .frame(maxWidth: .infinity)
    }

    /// The rest: "Rest", what comes next and its set, then the next move's instruction.
    private var restBody: some View {
        VStack(spacing: 0) {
            MovezText(state.headline, MovezType.overlayName, color: Tokens.text, alignment: .center, lineLimit: 1)
            MovezText(state.upNext, MovezType.upNext, color: Tokens.text, alignment: .center, lineLimit: 2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
            MovezText(state.kicker, MovezType.setKicker, color: Tokens.text3, alignment: .center, lineLimit: 1)
                .padding(.top, 6)
            instruction(MovezType.instructionSide, alignment: .center)
                .padding(.top, 22)
        }
        .frame(maxWidth: Self.centredWidth)
        .frame(maxWidth: .infinity)
    }

    /// The library's instruction, always shown in full. It is the one part of the body allowed
    /// to give way: a long instruction under a two-line name shrinks its type to fit the card
    /// rather than pushing the strip and the buttons off it.
    private func instruction(_ style: MovezTextStyle, alignment: TextAlignment) -> some View {
        MovezText(state.instruction, style, color: Tokens.text2, alignment: alignment, minimumScaleFactor: 0.7)
            .layoutPriority(-1)
    }

    private var nameStyle: MovezTextStyle {
        state.movementName.count > Self.longNameCharacters ? MovezType.setName : MovezType.overlayName
    }

    /// 24 pt on a set and whenever a side toggle shows; 28 pt on the warm-up, the cool-down and an
    /// end-range move.
    private var instructionStyle: MovezTextStyle {
        if state.isSideBlock { return MovezType.instructionSide }
        if case .set = state.segment { return MovezType.instructionSide }
        return MovezType.instruction
    }

    // MARK: - Actions

    /// Pause, Snooze and Skip. Snooze is never swapped for Done: the disc is Done.
    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(state.pauseLabel, action: actions.pause)
                .buttonStyle(SecondaryButtonStyle(size: .panel))
            if state.snoozeAvailable {
                Button("Snooze 5 min", action: actions.snooze)
                    .buttonStyle(AccentOutlineButtonStyle(size: .panel))
            }
            Button(state.skipLabel, action: actions.skip)
                .buttonStyle(LinkActionStyle(disabled: !state.skipEnabled))
                .disabled(!state.skipEnabled)
        }
        .frame(maxWidth: .infinity)
    }
}

/// What the strength overlay can ask the app to do. Defaults do nothing, which is what snapshots
/// want.
struct StrengthOverlayActions {
    /// The disc, Space, → and Return: Done on a set, Next on the warm-up, the cool-down and an
    /// end-range block, and skip on a rest.
    var disc: () -> Void = {}
    var pause: () -> Void = {}
    var snooze: () -> Void = {}
    var skip: () -> Void = {}
}

/// One screen's worth of a strength break: the dim, and the card over it.
///
/// When the session closes the card fades out over 240 ms while the window controller fades the
/// dim over 300 ms, the way a movement break leaves after Back to work.
struct StrengthOverlayScreen: View {
    @ObservedObject var viewModel: StrengthOverlayViewModel

    /// How long the card takes to fade once the break closes.
    static let cardFade: TimeInterval = 0.24

    var body: some View {
        ZStack {
            VisualEffectBackdrop()
            Tokens.dim.color
            card
                .opacity(viewModel.state.isClosed ? 0 : 1)
                .animation(.easeOut(duration: Self.cardFade), value: viewModel.state.isClosed)
        }
        .ignoresSafeArea()
    }

    /// The smooth meter is redrawn every frame from the clock; the stepped one, a paused one and
    /// every other body only move with the tick.
    @ViewBuilder
    private var card: some View {
        let state = viewModel.state
        if state.showsMeter, !state.reduceMotion, !state.isPaused {
            TimelineView(.animation) { _ in
                StrengthOverlayView(
                    state: state, actions: actions, animated: viewModel.animationsEnabled,
                    livePacer: viewModel.livePacer()
                )
            }
        } else {
            StrengthOverlayView(state: state, actions: actions, animated: viewModel.animationsEnabled)
        }
    }

    var actions: StrengthOverlayActions {
        StrengthOverlayActions(
            disc: viewModel.done,
            pause: viewModel.togglePause,
            snooze: viewModel.snooze,
            skip: viewModel.skip
        )
    }
}
