import Foundation

/// How long "Pause for" and "Extend pause" offer to stay quiet.
enum PauseOption: String, CaseIterable, Identifiable, Equatable {
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case restOfDay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fifteenMinutes: return "15 m"
        case .thirtyMinutes: return "30 m"
        case .oneHour: return "1 h"
        case .twoHours: return "2 h"
        case .restOfDay: return "Rest of day"
        }
    }

    /// nil means "until the working day ends".
    var seconds: Int? {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .twoHours: return 2 * 60 * 60
        case .restOfDay: return nil
        }
    }

    /// A pause already running can only be pushed out by a fixed amount.
    static let extendable: [PauseOption] = [.fifteenMinutes, .thirtyMinutes, .oneHour]
}

/// Everything the menu bar draws, as plain values.
///
/// The dropdown takes this rather than the view model, so a snapshot can render any mode exactly
/// without a coordinator, a scheduler or a history store anywhere near it.
struct MenuBarState: Equatable {
    enum Mode: String, Equatable {
        case sitting
        case paused
        case offHours
    }

    /// The minutes the menu offers to bring the next break forward by.
    static let makeDueMinutes = [5, 10, 15, 30]

    var mode: Mode = .sitting
    var minutesRemaining = 0
    /// 0 at the start of a sitting bout, 1 when the break falls due.
    var elapsedFraction: Double = 0
    var title = ""
    var subtitle = ""
    var stats = ""
    var longestBout = ""
    var isAdHocSession = false
    /// A break, heads-up or micro-break is on screen; the countdown label says so instead.
    var isBreaking = false
    var breakLabel = ""
    var pauseExpanded = false
    var extendExpanded = false

    /// "32m" · "‖ 42m" · "" — the text beside the menu-bar icon.
    ///
    /// The pause glyph rides in the text rather than in the icon: the handoff's menu bar reads
    /// "◌ ‖ 42m", and drawing it twice would be a stutter.
    var labelText: String {
        if isBreaking { return breakLabel }
        switch mode {
        case .sitting: return "\(minutesRemaining)m"
        case .paused: return "‖ \(minutesRemaining)m"
        case .offHours: return ""
        }
    }

    /// The header disc shows what is left; the menu-bar icon shows what has gone.
    var discProgress: Double { max(0, min(1, 1 - elapsedFraction)) }

    var discNumerals: String { mode == .sitting ? "\(minutesRemaining)" : "" }

    var discMode: TimerDiscMode {
        switch mode {
        case .sitting: return .full
        case .paused: return .dashed
        case .offHours: return .empty
        }
    }

    /// Off hours, the only break available is one the user asks for.
    var takeBreakLabel: String { "Take a break now" }

    /// Paused, the row is present but quiet: taking a break by hand is always allowed, it just
    /// should not be the thing the eye lands on.
    var takeBreakDimmed: Bool { mode == .paused }

    // MARK: - The strings

    static func title(mode: Mode, minutesRemaining: Int, indefinite: Bool = false) -> String {
        switch mode {
        case .sitting: return "Next break in \(minutesRemaining) min"
        case .paused: return indefinite ? "Paused" : "Paused · \(minutesRemaining) min left"
        case .offHours: return "Off hours"
        }
    }

    /// "Countdown resumes at 15:00 with 23 min left", or without the time when the pause has no
    /// end — a Focus filter decides when that one lifts, not the clock.
    static func pausedSubtitle(resumesAt: Date?, remainingMinutes: Int) -> String {
        guard let resumesAt else { return "Countdown resumes with \(remainingMinutes) min left" }
        return "Countdown resumes at \(MovezClock.label(resumesAt)) with \(remainingMinutes) min left"
    }

    /// "Breaks resume Monday at 9:00" — or today, or tomorrow, which read better than the day name.
    static func offHoursSubtitle(nextStart: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let nextStart else { return "No working days are switched on" }
        return "Breaks resume \(dayPhrase(nextStart, now: now, calendar: calendar)) at \(MovezClock.label(nextStart))"
    }

    static func dayPhrase(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    /// "Today · 3 done · 1 snoozed · 1 skipped", or the last working day's name off hours.
    static func statsLine(day: String, stats: DailyStats) -> String {
        "\(day) · \(stats.summary)"
    }

    static func longestBoutLine(seconds: Int) -> String {
        "Longest sitting bout \(AppCoordinator.duration(seconds))"
    }

}

/// What the menu bar can ask the app to do. Defaults do nothing, which is what snapshots want.
struct MenuBarActions {
    var takeBreakNow: () -> Void = {}
    var makeDue: (Int) -> Void = { _ in }
    var pause: (PauseOption) -> Void = { _ in }
    var resume: () -> Void = {}
    var extendPause: (PauseOption) -> Void = { _ in }
    var startSession: () -> Void = {}
    var endSession: () -> Void = {}
    var togglePauseOptions: () -> Void = {}
    var toggleExtendOptions: () -> Void = {}
    var openSettings: () -> Void = {}
    var quit: () -> Void = {}
}

/// A keyboard shortcut, in the two forms the menu needs: the key SwiftUI binds, and the glyphs
/// the row prints on the right.
struct MenuShortcutSpec: Equatable {
    var key: Character
    var label: String

    static let settings = MenuShortcutSpec(key: ",", label: "⌘,")
    static let quit = MenuShortcutSpec(key: "q", label: "⌘Q")
}
