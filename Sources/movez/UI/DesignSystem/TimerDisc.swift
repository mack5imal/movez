import SwiftUI

/// How a timer disc is drawn.
enum TimerDiscMode: Equatable {
    /// The ring shows the whole block.
    case full
    /// A per-side block: the ring shows only this half's share, offset to the half it belongs to.
    case halfShare(sideIndex: Int)
    /// Paused — a dashed outline with a pause glyph instead of a countdown.
    case dashed
    /// Off hours — an empty ring, no fill, no numerals.
    case empty
    /// The lead-in before a movement: a hollow disc, teal on the panel colour, so the seconds to
    /// read what is coming cannot be mistaken for the movement's own countdown. It fills when the
    /// movement starts.
    case leadIn
}

/// The accent disc with a draining ring. It is the overlay's Next button, the heads-up panel's
/// countdown and the menu bar's status glyph, all from one view.
struct TimerDisc: View {
    var size: CGFloat
    var progress: Double
    var numerals: String
    var label: String?
    var mode: TimerDiscMode = .full
    var strokeWidth: CGFloat?
    var numeralStyle: MovezTextStyle?
    var action: (() -> Void)?

    /// "0:42, NEXT →" — what VoiceOver reads when the disc is the button that advances.
    static func announcement(numerals: String, label: String?) -> String {
        guard let label, !label.isEmpty else { return numerals }
        return "\(numerals), \(label)"
    }

    /// The handoff specifies the 300 pt overlay disc: a 6 pt ring, 84 pt numerals and a 16 pt
    /// label. Every other size is that same disc scaled, which is how the 64 pt panel disc lands
    /// on its specified 17 pt numerals without a second table.
    private static let ringRatio: CGFloat = 6.0 / 300
    private static let numeralRatio: CGFloat = 84.0 / 300
    private static let labelRatio: CGFloat = 16.0 / 300
    /// Below this the disc is a status glyph, not a countdown, and loses its label.
    private static let labelThreshold: CGFloat = 120

    private var ringWidth: CGFloat {
        strokeWidth ?? max(Tokens.Metric.panelRingStroke, size * Self.ringRatio)
    }

    /// The ring inset so the stroke sits just inside the disc edge.
    private var ringInset: CGFloat { ringWidth / 2 + size * 0.033 }

    /// The fraction of the circle the ring may cover, and where it starts.
    private var arc: (start: Double, span: Double) {
        switch mode {
        case .halfShare(let index):
            return (Double(index) * 0.5, 0.5)
        default:
            return (0, 1)
        }
    }

    var body: some View {
        let disc = ZStack {
            background
            ring
            labels
        }
        .frame(width: size, height: size)

        if let action {
            Button(action: action) { disc }
                .buttonStyle(.plain)
                .accessibilityLabel(TimerDisc.announcement(numerals: numerals, label: label))
        } else {
            disc.accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch mode {
        case .dashed:
            Circle().strokeBorder(
                Tokens.text3.color,
                style: StrokeStyle(lineWidth: Tokens.Metric.panelRingStroke, dash: [4, 4])
            )
        case .empty:
            Circle().strokeBorder(Tokens.emptyRing.color, lineWidth: Tokens.Metric.panelRingStroke)
        case .full, .halfShare:
            Circle()
                .fill(Tokens.accent.color)
                .movezShadow(size >= 200 ? Tokens.Shadow.disc : Tokens.Shadow.panel)
        case .leadIn:
            Circle()
                .fill(Tokens.panelSolid.color)
                .overlay(Circle().strokeBorder(Tokens.secondaryBorder.color, lineWidth: max(1, ringWidth / 3)))
                .movezShadow(size >= 200 ? Tokens.Shadow.disc : Tokens.Shadow.panel)
        }
    }

    /// The ring's track and fill: ink on the teal disc, teal on the hollow one.
    private var ringColours: (track: MovezColor, fill: MovezColor) {
        mode == .leadIn ? (Tokens.accentTint, Tokens.accent) : (Tokens.ringTrack, Tokens.ink)
    }

    /// The numerals' colour: ink on the teal disc, teal on the hollow one.
    private var numeralColour: MovezColor {
        mode == .leadIn ? Tokens.accent : Tokens.ink
    }

    @ViewBuilder
    private var ring: some View {
        switch mode {
        case .dashed, .empty:
            EmptyView()
        case .full, .halfShare, .leadIn:
            ZStack {
                Circle()
                    .trim(from: arc.start, to: arc.start + arc.span)
                    .stroke(ringColours.track.color, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                Circle()
                    .trim(from: arc.start, to: arc.start + arc.span * max(0, min(1, progress)))
                    .stroke(ringColours.fill.color, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
            }
            // Rings start at twelve o'clock and drain clockwise.
            .rotationEffect(.degrees(-90))
            .padding(ringInset)
        }
    }

    @ViewBuilder
    private var labels: some View {
        switch mode {
        case .empty:
            EmptyView()
        case .dashed:
            MovezText("‖", MovezType.menuDisc, color: Tokens.text3)
        case .full, .halfShare, .leadIn:
            VStack(spacing: size * 0.008) {
                MovezText(numerals, numeralStyle ?? defaultNumeralStyle, color: numeralColour, alignment: .center)
                if let label, size >= Self.labelThreshold {
                    MovezText(label, scaled(MovezType.discLabel, Self.labelRatio), color: numeralColour.opacity(0.72), alignment: .center)
                }
            }
        }
    }

    private var defaultNumeralStyle: MovezTextStyle {
        scaled(size >= Self.labelThreshold ? MovezType.discNumerals : MovezType.panelDisc, Self.numeralRatio)
    }

    /// The style at this disc's size, never smaller than the menu-bar glyph needs.
    private func scaled(_ style: MovezTextStyle, _ ratio: CGFloat) -> MovezTextStyle {
        var scaled = style
        scaled.size = max(11, (size * ratio).rounded())
        return scaled
    }
}
