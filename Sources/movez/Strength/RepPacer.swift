import Foundation

/// What the rep meter shows at one moment of a set.
struct RepPacerState: Equatable {
    enum Stage: Equatable {
        /// A rep is under way.
        case rep
        /// The cue between the two sides of a per-side set: the meter empties and the counter reads
        /// "Switch sides".
        case switchSides
        /// Every rep is done; the set's grace runs on the set clock with the meter still.
        case finished
    }

    /// Where the fill is within the current rep.
    enum Phase: Equatable {
        case rising
        case holding
        case falling
        /// Between reps' worth of motion: the switch cue and after the last rep.
        case still
    }

    /// What the chevron shows, so that direction never depends on colour alone.
    enum Direction: Equatable {
        case up
        case down
        case hold
        case paused
        case stopped
    }

    /// How full the meter is. The stepped form is what Reduce Motion asks for: whole segments
    /// only, so that nothing on screen moves between reps.
    enum Level: Equatable {
        case smooth(Double)
        case stepped(filled: Int)
    }

    let stage: Stage
    /// 1-based, counting a side at a time on a per-side set.
    let rep: Int
    /// The reps the counter counts to, a side on a per-side set.
    let total: Int
    /// 0 for the first side (or a two-sided set), 1 from the switch cue on.
    let sideIndex: Int
    let phase: Phase
    let direction: Direction
    let level: Level

    /// "Rep 7 of 12", or "Switch sides" during the cue.
    var counter: String {
        stage == .switchSides ? "Switch sides" : "Rep \(rep) of \(total)"
    }
}

/// The rep meter's model: where a set's reps are as a function of the seconds it has run.
///
/// It knows nothing about strength mode, the library or the clock. It is handed a rep count and a
/// pace and asked about one moment, so a later mode can drive the same meter with its own numbers,
/// and a pause is nothing more than asking about the same moment again.
struct RepPacer: Equatable {
    let reps: Int
    let perSide: Bool
    /// The pause at the top of each rep, zero for most doses.
    let holdSeconds: Int
    /// One rep's rise and fall together; half of it is the rise.
    let paceSeconds: Int
    let switchSidesSeconds: Int

    /// Nil for a dose the meter cannot count: a time, a hold or a slow multi-part move, which has
    /// no meter at all.
    init?(reps: Int?, perSide: Bool, holdSeconds: Int?, paceSeconds: Int, switchSidesSeconds: Int) {
        guard let reps, reps > 0, paceSeconds > 0 else { return nil }
        self.reps = reps
        self.perSide = perSide
        self.holdSeconds = max(0, holdSeconds ?? 0)
        self.paceSeconds = paceSeconds
        self.switchSidesSeconds = switchSidesSeconds
    }

    /// One rep, hold included.
    var repSeconds: TimeInterval { TimeInterval(paceSeconds + holdSeconds) }
    /// Every rep of one side.
    var sideSeconds: TimeInterval { TimeInterval(reps) * repSeconds }
    /// When the meter stops: both sides and the cue between them on a per-side set.
    var meterSeconds: TimeInterval {
        perSide ? sideSeconds * 2 + TimeInterval(switchSidesSeconds) : sideSeconds
    }

    /// The meter `elapsed` seconds into the set.
    ///
    /// - Parameters:
    ///   - paused: shows the paused chevron; the caller freezes `elapsed` itself.
    ///   - stepped: Reduce Motion's whole-segment output.
    func state(at elapsed: TimeInterval, paused: Bool = false, stepped: Bool = false) -> RepPacerState {
        let elapsed = max(0, elapsed)
        var sideIndex = 0
        var sideElapsed = elapsed

        if perSide, elapsed >= sideSeconds {
            sideIndex = 1
            let cueEnds = sideSeconds + TimeInterval(switchSidesSeconds)
            if elapsed < cueEnds {
                return make(.switchSides, rep: reps, side: 1, phase: .still, fill: 0, filled: 0,
                            paused: paused, stepped: stepped)
            }
            sideElapsed = elapsed - cueEnds
        }

        guard sideElapsed < sideSeconds else {
            return make(.finished, rep: reps, side: sideIndex, phase: .still, fill: 0, filled: reps,
                        paused: paused, stepped: stepped)
        }

        let index = min(reps - 1, Int((sideElapsed / repSeconds).rounded(.down)))
        let within = sideElapsed - TimeInterval(index) * repSeconds
        let half = TimeInterval(paceSeconds) / 2
        let phase: RepPacerState.Phase
        let fill: Double
        if within < half {
            phase = .rising
            fill = Self.easeInOutSine(within / half)
        } else if within < half + TimeInterval(holdSeconds) {
            phase = .holding
            fill = 1
        } else {
            phase = .falling
            fill = 1 - Self.easeInOutSine((within - half - TimeInterval(holdSeconds)) / half)
        }
        return make(.rep, rep: index + 1, side: sideIndex, phase: phase, fill: fill, filled: index,
                    paused: paused, stepped: stepped)
    }

    // swiftlint:disable:next function_parameter_count
    private func make(
        _ stage: RepPacerState.Stage,
        rep: Int,
        side: Int,
        phase: RepPacerState.Phase,
        fill: Double,
        filled: Int,
        paused: Bool,
        stepped: Bool
    ) -> RepPacerState {
        let direction: RepPacerState.Direction
        if paused {
            direction = .paused
        } else {
            switch phase {
            case .rising: direction = .up
            case .holding: direction = .hold
            case .falling: direction = .down
            case .still: direction = .stopped
            }
        }
        return RepPacerState(
            stage: stage,
            rep: rep,
            total: reps,
            sideIndex: side,
            phase: phase,
            direction: direction,
            level: stepped ? .stepped(filled: filled) : .smooth(min(1, max(0, fill)))
        )
    }

    /// The design's even rhythm: slow at the ends of a rep, quickest through the middle.
    static func easeInOutSine(_ fraction: Double) -> Double {
        let fraction = min(1, max(0, fraction))
        return (1 - cos(Double.pi * fraction)) / 2
    }
}
