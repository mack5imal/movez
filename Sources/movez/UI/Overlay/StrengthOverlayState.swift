import Foundation

/// Everything a strength or end-range break's overlay draws, as plain values.
///
/// A sibling of `OverlayState` rather than more fields on it: a strength break has a rep meter, a
/// rest and a dose, and no end screen, so sharing one value would leave half of either unused and
/// let a Movement view read a strength field by mistake.
struct StrengthOverlayState: Equatable {
    /// The segment on screen, nil once the break has closed.
    var segment: StrengthSessionTimeline.Kind?
    /// The break has ended on its own; the overlay dismisses itself, with no end screen.
    var isClosed = false

    // Header
    /// The mode the break was built in, whose badge leads the header. An end-range break belongs
    /// to Strength, so it wears the same badge.
    var mode: ModeDefinition = .strength
    var eyebrow = ""
    var headerTrailing = ""

    // Body
    /// "Set 2 of 3", "Warm-up", "Cool-down"; empty on an end-range block.
    var kicker = ""
    /// "Rest" during a rest, which shows the next set underneath it.
    var headline = ""
    var movementName = ""
    /// The dose line, after the display rule: "10 each side".
    var dose = ""
    /// The dose's modifier line: "Alternating · 2 s hold".
    var doseModifier: String?
    var instruction = ""
    /// "Up next: Push-up · 10 reps", during a rest.
    var upNext = ""
    /// The rep meter, on a set whose dose it counts and the lead-in before one; nil means no meter.
    var pacer: RepPacerState?
    /// "Rep 7 of 12" or "Switch sides", beside the meter.
    var counter = ""
    var isSideBlock = false
    var side: BreakSide = .none
    /// macOS Reduce Motion: the meter is the stepped ladder and the body does not crossfade.
    var reduceMotion = false

    // Disc
    var discNumerals = ""
    var discLabel = ""
    var discProgress: Double = 0
    var discMode: TimerDiscMode = .full

    // Strip and actions
    var strip: [StripItem] = []
    var isPaused = false
    var snoozeAvailable = true
    var skipEnabled = false
    var skipsToday = 0

    /// The body a rep-counted set has: the meter beside a left-aligned column. Everything else,
    /// rests included, is one centred column.
    var showsMeter: Bool { pacer != nil && !isRest }
    var isRest: Bool {
        if case .rest = segment { return true }
        return false
    }

    var skipLabel: String { "Skip · \(skipsToday) today" }
    var pauseLabel: String { isPaused ? "Resume" : "Pause" }

    /// "Set 2 of 3"
    static func setKicker(_ number: Int, of total: Int) -> String { "Set \(number) of \(total)" }
    static let warmUpKicker = "Warm-up"
    static let coolDownKicker = "Cool-down"
    static let restHeadline = "Rest"

    /// "Up next: Push-up · 10 reps"
    static func upNext(movement: String, dose: String) -> String {
        dose.isEmpty ? "Up next: \(movement)" : "Up next: \(movement) · \(dose)"
    }
}
