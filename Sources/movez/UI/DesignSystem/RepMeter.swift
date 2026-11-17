import SwiftUI

/// What the rep meter draws for one pacer state, kept apart from the view so a test can ask which
/// look a state produces without rendering anything.
enum RepMeterLook: Equatable {
    /// One step of the Reduce Motion ladder, counted from the bottom.
    enum Segment: Equatable {
        case done
        case current
        case later
    }

    /// The default look: a fill that rises and falls with each rep, and a chevron that says which.
    case smooth(fillHeight: CGFloat, chevron: RepPacerState.Direction)
    /// Reduce Motion: one whole segment per rep, nothing moving between reps.
    case stepped(segments: [Segment])
    /// Between the sides of a per-side set: the meter empties and shows the swap glyph.
    case switchCue

    /// The look for `state`. The pacer state is the same either way; Reduce Motion alone decides
    /// between the ladder and the fill, so the two can never disagree about where the set is.
    static func make(for state: RepPacerState, reduceMotion: Bool) -> RepMeterLook {
        if state.stage == .switchSides { return .switchCue }
        if reduceMotion {
            return .stepped(segments: segments(for: state))
        }
        return .smooth(fillHeight: fillHeight(for: fraction(of: state)), chevron: state.direction)
    }

    /// The fill's height for a fraction `p` of a rep's travel: one pill's worth at rest, the whole
    /// track at the top.
    static func fillHeight(for fraction: Double) -> CGFloat {
        let travel = Tokens.Metric.repMeter.height - Tokens.Metric.repMeterMinFill
        return Tokens.Metric.repMeterMinFill + travel * CGFloat(min(1, max(0, fraction)))
    }

    private static func fraction(of state: RepPacerState) -> Double {
        switch state.level {
        case .smooth(let fraction): return fraction
        // A stepped reading carries no position within the rep, so the fill rests.
        case .stepped: return 0
        }
    }

    private static func segments(for state: RepPacerState) -> [Segment] {
        let total = max(0, state.total)
        let done: Int
        switch state.level {
        case .stepped(let filled): done = filled
        case .smooth: done = state.stage == .finished ? total : max(0, state.rep - 1)
        }
        let current: Int? = state.stage == .rep ? state.rep - 1 : nil
        return (0..<total).map { index in
            if index == current { return .current }
            return index < done ? .done : .later
        }
    }
}

/// The rep meter: a 64×264 pill that fills from the bottom with each rep, with the rep counter
/// under it.
///
/// It is handed a `RepPacerState` and knows nothing about strength, the library or the clock, so
/// any mode that counts reps can drive it.
struct RepMeter: View {
    let state: RepPacerState
    var reduceMotion = false

    private static let size = Tokens.Metric.repMeter
    /// From the meter to the counter.
    private static let counterGap: CGFloat = 18
    /// The chevron's top sits this far below the fill's top edge.
    private static let chevronInset: CGFloat = 16

    var look: RepMeterLook { RepMeterLook.make(for: state, reduceMotion: reduceMotion) }

    /// What VoiceOver reads for the whole meter: the counter ("Rep 7 of 12", or "Switch sides"),
    /// since the fill itself carries no words.
    var announcement: String { state.counter }

    var body: some View {
        VStack(spacing: Self.counterGap) {
            meter
                .frame(width: Self.size.width, height: Self.size.height)
            MovezText(
                state.counter,
                MovezType.repCounter,
                color: state.stage == .switchSides ? Tokens.accent : Tokens.text,
                alignment: .center,
                lineLimit: 1
            )
        }
        .frame(width: Tokens.Metric.repMeterColumn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(announcement)
    }

    @ViewBuilder
    private var meter: some View {
        switch look {
        case let .smooth(fillHeight, chevron):
            ZStack(alignment: .bottom) {
                Capsule().fill(Tokens.accentTint.color)
                Capsule().fill(Tokens.accent.color).frame(height: fillHeight)
                RepMeterChevron(direction: chevron)
                    .padding(.bottom, fillHeight - Self.chevronInset - RepMeterChevron.size.height)
            }
        case .stepped(let segments):
            ladder(segments)
        case .switchCue:
            ZStack {
                Capsule().fill(Tokens.accentTint.color)
                SwitchSidesGlyph()
                    .stroke(Tokens.accent.color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: RepMeterChevron.size.width, height: RepMeterChevron.size.height)
            }
        }
    }

    private func ladder(_ segments: [RepMeterLook.Segment]) -> some View {
        VStack(spacing: Tokens.Metric.ladderGap) {
            // Drawn top to bottom, so the ladder fills from the bottom.
            ForEach(Array(segments.enumerated().reversed()), id: \.offset) { _, segment in
                let shape = RoundedRectangle(cornerRadius: Tokens.Radius.ladderSegment, style: .continuous)
                shape
                    .fill((segment == .done ? Tokens.accent : Tokens.accentTint).color)
                    .overlay(
                        shape.strokeBorder(segment == .current ? Tokens.accent.color : .clear, lineWidth: 2)
                    )
            }
        }
    }
}

/// The chevron on the fill: up while rising, down while falling, `=` while holding and `‖` while
/// paused, so the direction never depends on colour.
struct RepMeterChevron: View {
    var direction: RepPacerState.Direction

    static let size = CGSize(width: 28, height: 16)

    var body: some View {
        Group {
            switch direction {
            case .up: ChevronShape(pointsUp: true).stroke(Tokens.ink.color, style: Self.style)
            case .down: ChevronShape(pointsUp: false).stroke(Tokens.ink.color, style: Self.style)
            case .hold: BarsShape(vertical: false).stroke(Tokens.ink.color, style: Self.style)
            case .paused: BarsShape(vertical: true).stroke(Tokens.ink.color, style: Self.style)
            case .stopped: Color.clear
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }

    private static let style = StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)

    private struct ChevronShape: Shape {
        var pointsUp: Bool

        func path(in rect: CGRect) -> Path {
            let inset: CGFloat = 2
            let tip = pointsUp ? rect.minY + inset : rect.maxY - inset
            let base = pointsUp ? rect.maxY - inset : rect.minY + inset
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + inset, y: base))
            path.addLine(to: CGPoint(x: rect.midX, y: tip))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: base))
            return path
        }
    }

    /// Two 18 pt bars: side by side for the pause, one above the other for the hold.
    private struct BarsShape: Shape {
        var vertical: Bool

        func path(in rect: CGRect) -> Path {
            var path = Path()
            let half: CGFloat = 9
            let apart: CGFloat = 3.5
            if vertical {
                for column in [rect.midX - apart, rect.midX + apart] {
                    path.move(to: CGPoint(x: column, y: rect.midY - half + 2))
                    path.addLine(to: CGPoint(x: column, y: rect.midY + half - 2))
                }
            } else {
                for row in [rect.midY - apart, rect.midY + apart] {
                    path.move(to: CGPoint(x: rect.midX - half, y: row))
                    path.addLine(to: CGPoint(x: rect.midX + half, y: row))
                }
            }
            return path
        }
    }
}

/// The ⇄ of the switch-sides cue: an arrow each way.
struct SwitchSidesGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        // The arrows are drawn on a 28×16 grid and scaled to the rect.
        func point(_ gridX: CGFloat, _ gridY: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + gridX / 28 * width, y: rect.minY + gridY / 16 * height)
        }
        var path = Path()
        path.move(to: point(3, 4.5))
        path.addLine(to: point(25, 4.5))
        path.move(to: point(21, 1.5))
        path.addLine(to: point(25, 4.5))
        path.addLine(to: point(21, 7.5))
        path.move(to: point(25, 11.5))
        path.addLine(to: point(3, 11.5))
        path.move(to: point(7, 8.5))
        path.addLine(to: point(3, 11.5))
        path.addLine(to: point(7, 14.5))
        return path
    }
}
