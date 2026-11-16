import Foundation

/// Which half of a per-side block is running.
enum BreakSide: String, Equatable {
    case none
    case left
    case right

    /// Spelled out rather than derived from the raw value, so the words on the toggle are the
    /// design's and a renamed case cannot change them.
    var label: String {
        switch self {
        case .none: return ""
        case .left: return "Left"
        case .right: return "Right"
        }
    }
    var index: Int { self == .right ? 1 : 0 }
}

/// Everything the overlay draws, as plain values.
///
/// The view takes this rather than the view model, so a snapshot can render any state exactly
/// without a clock, a scheduler or a history store anywhere near it.
struct OverlayState: Equatable {
    /// The heads-up's and the overlay's eyebrow. Routines have no names: they are drawn at random,
    /// and a title could only describe whichever region the draw landed on.
    static let movementBreakEyebrow = "MOVEMENT BREAK"

    /// Where the view model is in its break. The view has nothing to draw for a finished break:
    /// it leaves the screen as it ends, with no end screen (DECISIONS 76).
    enum Phase: Equatable {
        case running
        case complete
    }

    // Header
    /// The mode the break was built in, whose badge leads the header.
    var mode: ModeDefinition = .movement
    var eyebrow = ""
    var headerTrailing = ""

    // Disc
    var discNumerals = ""
    var discLabel = "NEXT →"
    var discProgress: Double = 0
    var discMode: TimerDiscMode = .full

    // Body
    var movementName = ""
    var instruction = ""
    var isSideBlock = false
    var side: BreakSide = .none

    // Strip and actions
    var strip: [StripItem] = []
    var snoozeAvailable = true
    var doneAvailable = false
    var skipEnabled = false
    var isPaused = false
    var skipsToday = 0

    var skipLabel: String { "Skip · \(skipsToday) today" }
    var pauseLabel: String { isPaused ? "Resume" : "Pause" }

    /// The counts small enough to spell out are: "Four", not "4".
    static func numberWord(_ count: Int) -> String {
        switch count {
        case 1: return "One"
        case 2: return "Two"
        case 3: return "Three"
        case 4: return "Four"
        case 5: return "Five"
        case 6: return "Six"
        default: return "\(count)"
        }
    }

    /// "4:12" from seconds, always m:ss.
    static func clock(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// "−0:05": time until something starts, which wears a minus (U+2212) so it never reads as the
    /// time a movement has left.
    static func untilStart(_ seconds: Int) -> String {
        "−\(clock(seconds))"
    }
}

/// What the overlay can ask the app to do. Defaults do nothing, which is what snapshots want.
struct OverlayActions {
    var next: () -> Void = {}
    var snooze: () -> Void = {}
    var done: () -> Void = {}
    var skip: () -> Void = {}
    var pause: () -> Void = {}
    var chooseSide: (BreakSide) -> Void = { _ in }
}
