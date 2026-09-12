import Foundation

/// Which half of a per-side block is running.
enum BreakSide: String, Equatable {
    case none
    case left
    case right

    var label: String { rawValue.capitalized }
    var index: Int { self == .right ? 1 : 0 }
}

/// Everything the overlay draws, as plain values.
///
/// The view takes this rather than the view model, so a snapshot can render any state exactly
/// without a clock, a scheduler or a history store anywhere near it.
struct OverlayState: Equatable {
    enum Phase: Equatable {
        case running
        case complete
    }

    var phase: Phase = .running

    // Header
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
    var instructionCollapsed = false
    var isSideBlock = false
    var side: BreakSide = .none

    // Strip and actions
    var strip: [StripItem] = []
    var snoozeAvailable = true
    var doneAvailable = false
    var skipEnabled = false
    var skipsToday = 0

    // End state
    var completionTitle = ""
    var endSummary = ""
    var streak = 0

    var skipLabel: String { "Skip · \(skipsToday) today" }
    var helperLabel: String { instructionCollapsed ? "Show instruction" : "I know this one" }

    /// "Four movements done. Next break at 12:05." — the counts small enough to spell out are.
    static func summary(movements: Int, nextBreakAt: String) -> String {
        "\(numberWord(movements)) movements done. Next break at \(nextBreakAt)."
    }

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
}

/// What the overlay can ask the app to do. Defaults do nothing, which is what snapshots want.
struct OverlayActions {
    var next: () -> Void = {}
    var snooze: () -> Void = {}
    var done: () -> Void = {}
    var skip: () -> Void = {}
    var toggleCollapsed: () -> Void = {}
    var chooseSide: (BreakSide) -> Void = { _ in }
    var backToWork: () -> Void = {}
}
