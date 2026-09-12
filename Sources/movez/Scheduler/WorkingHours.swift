import Foundation

/// One day's working window, as minutes from local midnight.
struct DayHours: Codable, Equatable, Hashable {
    var enabled: Bool
    var startMinutes: Int
    var endMinutes: Int

    static let off = DayHours(enabled: false, startMinutes: 9 * 60, endMinutes: 18 * 60)
    static let nineToSix = DayHours(enabled: true, startMinutes: 9 * 60, endMinutes: 18 * 60)

    var isValid: Bool { !enabled || startMinutes < endMinutes }

    /// "9:00" — no leading zero on the hour, which is how the settings window shows it.
    static func label(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    var label: String { "\(Self.label(minutes: startMinutes))–\(Self.label(minutes: endMinutes))" }
}

enum WorkingHoursError: LocalizedError, Equatable {
    case endNotAfterStart(weekdayLabel: String)

    var errorDescription: String? {
        switch self {
        case .endNotAfterStart(let day): return "\(day) ends before it starts. Working hours cannot cross midnight."
        }
    }
}

/// One window per day. The scheduler stays quiet outside it unless the user starts a session by
/// hand.
struct WorkingHours: Codable, Equatable, Hashable {
    /// Indexed by `Calendar` weekday − 1, so index 0 is Sunday.
    var days: [DayHours]

    /// Monday through Friday, in display order.
    static let displayOrder = [2, 3, 4, 5, 6, 7, 1]
    static let shortNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// Every day, all day — the shape the tests use when working hours are not what is under test.
    static let alwaysOn = WorkingHours(
        days: Array(repeating: DayHours(enabled: true, startMinutes: 0, endMinutes: 24 * 60), count: 7)
    )

    static let standard = WorkingHours(days: [
        .off,        // Sunday
        .nineToSix,  // Monday
        .nineToSix,
        .nineToSix,
        .nineToSix,
        .nineToSix,  // Friday
        .off         // Saturday
    ])

    init(days: [DayHours]) {
        self.days = days.count == 7 ? days : Array(repeating: .nineToSix, count: 7)
    }

    func hours(on date: Date, calendar: Calendar) -> DayHours {
        days[(calendar.component(.weekday, from: date) - 1) % 7]
    }

    func isWithin(_ date: Date, calendar: Calendar) -> Bool {
        let day = hours(on: date, calendar: calendar)
        guard day.enabled else { return false }
        let minutes = Self.minutes(of: date, calendar: calendar)
        return minutes >= day.startMinutes && minutes < day.endMinutes
    }

    /// The next time the working day opens, searching up to a week ahead.
    func nextStart(after date: Date, calendar: Calendar) -> Date? {
        boundary(after: date, calendar: calendar) { $0.startMinutes }
    }

    /// The next time the working day closes.
    func nextEnd(after date: Date, calendar: Calendar) -> Date? {
        boundary(after: date, calendar: calendar) { $0.endMinutes }
    }

    /// Today's closing time, used by "Pause for the rest of the day".
    func endOfToday(_ date: Date, calendar: Calendar) -> Date? {
        let day = hours(on: date, calendar: calendar)
        guard day.enabled else { return nil }
        return Self.date(startOfDay: calendar.startOfDay(for: date), minutes: day.endMinutes)
    }

    private func boundary(
        after date: Date,
        calendar: Calendar,
        minutes selector: (DayHours) -> Int
    ) -> Date? {
        for offset in 0...8 {
            guard let candidateDay = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            let day = hours(on: candidateDay, calendar: calendar)
            guard day.enabled else { continue }
            let midnight = calendar.startOfDay(for: candidateDay)
            let moment = Self.date(startOfDay: midnight, minutes: selector(day))
            if moment > date { return moment }
        }
        return nil
    }

    func validate() -> [WorkingHoursError] {
        Self.displayOrder.compactMap { weekday in
            let day = days[weekday - 1]
            guard !day.isValid else { return nil }
            return .endNotAfterStart(weekdayLabel: Self.shortNames[weekday - 1])
        }
    }

    /// "Mon–Fri · 9:00–18:00", collapsing runs of consecutive days that share a window.
    func summary() -> String {
        var groups: [DayRun] = []
        for (position, weekday) in Self.displayOrder.enumerated() {
            let day = days[weekday - 1]
            guard day.enabled else { continue }
            if var previous = groups.last, previous.hours == day, previous.last == position - 1 {
                previous.last = position
                groups[groups.count - 1] = previous
            } else {
                groups.append(DayRun(first: position, last: position, hours: day))
            }
        }
        guard !groups.isEmpty else { return "Off" }
        return groups.map(\.label).joined(separator: ", ")
    }

    /// A run of consecutive days sharing one window, as positions in `displayOrder`.
    private struct DayRun {
        var first: Int
        var last: Int
        var hours: DayHours

        var label: String {
            let firstName = WorkingHours.shortNames[WorkingHours.displayOrder[first] - 1]
            let lastName = WorkingHours.shortNames[WorkingHours.displayOrder[last] - 1]
            let days = first == last ? firstName : "\(firstName)–\(lastName)"
            return "\(days) · \(hours.label)"
        }
    }

    static func minutes(of date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func date(startOfDay: Date, minutes: Int) -> Date {
        startOfDay.addingTimeInterval(TimeInterval(minutes * 60))
    }
}
