import SwiftUI

// design: overlay

/// The break itself: a 1000×660 card centred on each display, with the timer disc sitting on its
/// top-right corner.
struct OverlayView: View {
    var state: OverlayState
    var actions = OverlayActions()
    var animated = true

    var body: some View {
        OverlayCard(disc: disc) {
            runningBody
        }
    }

    private var disc: TimerDisc? {
        TimerDisc(
            size: Tokens.Metric.overlayDisc,
            progress: state.discProgress,
            numerals: state.discNumerals,
            label: state.discLabel,
            mode: state.discMode,
            action: actions.next
        )
    }

    private var runningBody: some View {
        VStack(spacing: 0) {
            OverlayHeader(mode: state.mode, trailing: state.headerTrailing)
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
        .padding(OverlayCardLayout.contentInsets)
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

/// Measurements the card and the bodies inside it share.
enum OverlayCardLayout {
    /// The card's padding, from the handoff: 56 80 44.
    static let contentInsets = EdgeInsets(top: 56, leading: 80, bottom: 44, trailing: 80)
}

/// The overlay's frame, shared by every kind of break: the card, its border and shadow, and the
/// timer disc on its top-right corner.
struct OverlayCard<Content: View>: View {
    var disc: TimerDisc?
    @ViewBuilder var content: Content

    /// The card's own size, from the handoff.
    private let card = Tokens.Metric.overlayCard
    private let discSize = Tokens.Metric.overlayDisc
    /// On a 1440×900 screen the handoff puts the card at (220, 130) and the disc at (1070, 60),
    /// so the disc's centre sits on the card's right edge, 70 pt below its top corner.
    private var discCentreBelowTop: CGFloat { Tokens.Metric.overlayDiscCentreBelowTop }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .frame(width: card.width, height: card.height)
                .background(Tokens.panel.color)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.overlay, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.overlay, style: .continuous)
                        .strokeBorder(Tokens.panelBorder.color, lineWidth: 1)
                )
                .movezShadow(Tokens.Shadow.overlay)

            if let disc {
                disc.offset(x: card.width - discSize / 2, y: discCentreBelowTop - discSize / 2)
            }
        }
        .frame(width: card.width, height: card.height)
    }
}

/// The overlay's header row: the mode badge on the left and the time left on the right.
///
/// The badge comes from the mode the break was built in, so a Movement break says MOVEMENT BREAK
/// behind its glyph and a strength or end-range break says STRENGTH BREAK behind its own.
struct OverlayHeader: View {
    var mode: ModeDefinition
    var trailing: String

    var badge: ModeBadge {
        ModeBadge(definition: mode, size: .overlay, label: .breakEyebrow)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            badge
            Spacer(minLength: 24)
            MovezText(trailing, MovezType.eyebrowOverlay, color: Tokens.text2)
        }
        // Keeps the header clear of the disc sitting on the corner.
        .padding(.trailing, 200)
    }
}

/// The Left / Right pill on a per-side block.
struct SideToggle: View {
    var side: BreakSide
    /// The smaller pill that sits at the right end of a dose line beside the rep meter.
    var compact = false
    var choose: (BreakSide) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment(.left)
            segment(.right)
        }
        .padding(compact ? 4 : 6)
        .background(Capsule().fill(Tokens.accentTint.color))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Side")
    }

    private func segment(_ target: BreakSide) -> some View {
        Button { choose(target) } label: {
            MovezText(
                target.label,
                compact ? MovezType.sidePillCompact : MovezType.sideToggle,
                color: side == target ? Tokens.ink : Tokens.text3,
                alignment: .center
            )
            .padding(.horizontal, compact ? 22 : 30)
            .padding(.vertical, 6)
            .background(Capsule().fill(side == target ? Tokens.accent.color : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(side == target ? [.isButton, .isSelected] : .isButton)
    }
}

/// Shrinks the break card to fit a display smaller than the one the handoff draws it for.
///
/// The card is a fixed 1000 × 660 pt with the disc hanging off its top-right corner, so a centred
/// break needs about 1350 × 850 pt. On a smaller display (an iPad over Sidecar, a projector, a
/// scaled laptop panel) the disc, which is the Next and Done control, was cut off. Anything that
/// big or bigger is drawn exactly as designed.
struct FitsOverlayCard: ViewModifier {
    static let margin: CGFloat = 24

    /// The card with the disc's overhang on both sides, so it can sit centred, and a margin.
    static var footprint: CGSize {
        let card = Tokens.Metric.overlayCard
        let disc = Tokens.Metric.overlayDisc
        let overhangAbove = disc / 2 - Tokens.Metric.overlayDiscCentreBelowTop
        return CGSize(width: card.width + disc + margin * 2, height: card.height + overhangAbove * 2 + margin * 2)
    }

    static func scale(for available: CGSize) -> CGFloat {
        min(1, available.width / footprint.width, available.height / footprint.height)
    }

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .scaleEffect(Self.scale(for: geometry.size))
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
