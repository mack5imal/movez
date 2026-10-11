import SwiftUI

/// The break itself: a 1000×660 card centred on the active display, with the timer disc sitting
/// on its top-right corner.
struct OverlayView: View {
    var state: OverlayState
    var actions = OverlayActions()
    var animated = true

    /// The card's own size, from the handoff.
    private let card = Tokens.Metric.overlayCard
    private let disc = Tokens.Metric.overlayDisc
    /// On a 1440×900 screen the handoff puts the card at (220, 130) and the disc at (1070, 60),
    /// so the disc's centre sits on the card's right edge, 70 pt below its top corner.
    private let discCentreBelowTop: CGFloat = 80

    var body: some View {
        ZStack(alignment: .topLeading) {
            cardBody
                .frame(width: card.width, height: card.height)
                .background(Tokens.panel.color)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.overlay, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.overlay, style: .continuous)
                        .strokeBorder(Tokens.panelBorder.color, lineWidth: 1)
                )
                .movezShadow(Tokens.Shadow.overlay)

            if state.phase == .running {
                TimerDisc(
                    size: disc,
                    progress: state.discProgress,
                    numerals: state.discNumerals,
                    label: state.discLabel,
                    mode: state.discMode,
                    action: actions.next
                )
                .offset(x: card.width - disc / 2, y: discCentreBelowTop - disc / 2)
            }
        }
        .frame(width: card.width, height: card.height)
    }

    @ViewBuilder
    private var cardBody: some View {
        if state.phase == .complete {
            OverlayEndView(state: state, actions: actions)
        } else {
            runningBody
        }
    }

    private var runningBody: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 0)
            movementBody
                .frame(maxWidth: 780)
                .id(state.movementName)
                .transition(animated ? .opacity : .identity)
            Spacer(minLength: 0)
            SequenceStrip(items: state.strip)
                .padding(.top, 28)
            actionRow
                .padding(.top, 24)
        }
        .padding(EdgeInsets(top: 56, leading: 80, bottom: 44, trailing: 80))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            MovezText(state.eyebrow, MovezType.eyebrowOverlay, color: Tokens.accent)
            Spacer(minLength: 24)
            MovezText(state.headerTrailing, MovezType.eyebrowOverlay, color: Tokens.text2)
        }
        // Keeps the header clear of the disc sitting on the corner.
        .padding(.trailing, 200)
    }

    @ViewBuilder
    private var movementBody: some View {
        VStack(spacing: state.isSideBlock ? 20 : 18) {
            MovezText(
                state.movementName,
                state.isSideBlock ? MovezType.overlayNameSide : MovezType.overlayName,
                color: Tokens.text,
                alignment: .center,
                // One line that shrinks to fit. Allowed to wrap, a long name took two lines and the
                // card's fixed height squeezed it down to one with an ellipsis.
                lineLimit: 1,
                minimumScaleFactor: 0.5
            )
            .layoutPriority(1)

            if state.isSideBlock {
                SideToggle(side: state.side, choose: actions.chooseSide)
            }

            // Always shown. It used to collapse behind "I know this one", which nobody needs: the
            // instruction is the reason the break has a screen at all.
            MovezText(
                state.instruction,
                state.isSideBlock ? MovezType.instructionSide : MovezType.instruction,
                color: Tokens.text2,
                alignment: .center
            )
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(state.pauseLabel, action: actions.pause)
                .buttonStyle(SecondaryButtonStyle(size: .panel))
            if state.doneAvailable {
                Button("Done", action: actions.done)
                    .buttonStyle(AccentOutlineButtonStyle(size: .panel))
            } else if state.snoozeAvailable {
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

/// The Left / Right pill on a per-side block.
struct SideToggle: View {
    var side: BreakSide
    var choose: (BreakSide) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment(.left)
            segment(.right)
        }
        .padding(6)
        .background(Capsule().fill(Tokens.accentTint.color))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Side")
    }

    private func segment(_ target: BreakSide) -> some View {
        Button { choose(target) } label: {
            MovezText(
                target.label,
                MovezType.sideToggle,
                color: side == target ? Tokens.ink : Tokens.text3,
                alignment: .center
            )
            .padding(.horizontal, 30)
            .padding(.vertical, 6)
            .background(Capsule().fill(side == target ? Tokens.accent.color : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(side == target ? [.isButton, .isSelected] : .isButton)
    }
}

/// What the other displays show while a break runs.
struct OtherDisplayLabel: View {
    var timeLeft: String

    var body: some View {
        MovezText("MOVEMENT BREAK · \(timeLeft)", MovezType.eyebrowOverlay, color: Tokens.text2, alignment: .center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
