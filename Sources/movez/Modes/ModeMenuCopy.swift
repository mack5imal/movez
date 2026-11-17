import Foundation

/// The dropdown's words for a mode that plans its day.
///
/// They live in `Modes/` beside `ModeDayProgress` so the menu never asks which mode it is showing:
/// a mode with a day plan hands the menu its progress, and these strings are all the menu reads
/// from it. A mode without one (Movement) has no progress, so its header keeps no subtitle and its
/// away state keeps its own sentence. These strings are what the Strength dropdown adds to the
/// shared `MenuBarView`.
extension ModeDayProgress {
    /// "Strength · A day · break 2 of 3", or "Strength · end-range break" once the day's strength
    /// breaks are done and every full break left today is an end-range one.
    var menuSubtitle: String {
        guard let breakNumber else { return "Strength · end-range break" }
        return "Strength · \(dayLetter.rawValue) day · break \(breakNumber) of \(breaksPerDay)"
    }

    /// The away subtitle, which says what the user's away setting is doing to the countdown and
    /// that the absence did not use up a strength break: away time is never a break, and never
    /// described as rest.
    ///
    /// After the day's strength breaks the second sentence is left off. The design only words the
    /// strength case, and the header already names the end-range break once the user is back.
    func awaySubtitle(behaviour: AwayBehaviour, minutesLeft: Int) -> String {
        switch (behaviour, breakNumber) {
        case let (.reset, number?):
            return "Timer restarts when you’re back. Strength break \(number) of \(breaksPerDay) is still next."
        case let (.pause, number?):
            return "Countdown paused with \(minutesLeft) min left. Strength break \(number) of \(breaksPerDay) is still next."
        case (.reset, nil):
            return "Timer restarts when you’re back."
        case (.pause, nil):
            return "Countdown paused with \(minutesLeft) min left."
        }
    }
}
