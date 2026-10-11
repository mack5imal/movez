import Foundation

/// One movement the user actually did.
struct MovementCompletion: Codable, Equatable, Identifiable {
    var movementId: String
    var at: Date
    var seconds: Int
    var routineId: UUID?

    var id: String { "\(movementId)-\(at.timeIntervalSince1970)" }
}

/// How one break ended.
enum BreakResult: String, Codable, Equatable, CaseIterable {
    case done
    case skipped
    case snoozed
    /// A five-minute absence the scheduler credited as a break.
    case credited

    /// Snoozing is a deferral, so it neither counts for nor against the streak.
    var affectsStreak: Bool { self != .snoozed }
    var countsAsCompleted: Bool { self == .done || self == .credited }
}

/// One break, as it happened.
struct BreakRecord: Codable, Equatable, Identifiable {
    /// What every full break is recorded as, now that routines have no names. The field keeps its
    /// name and its type so that history written before still decodes.
    static let movementBreakName = "Movement break"

    var at: Date
    var routineName: String
    var outcome: BreakResult
    var completedBlocks: Int
    var totalBlocks: Int

    var id: String { "\(at.timeIntervalSince1970)-\(routineName)" }
}

/// A day the user actually used movez on, and what it came to.
struct RecordedDay: Equatable {
    var key: String
    var date: Date
    var stats: DailyStats
}

/// The counters the menu bar shows for a day.
struct DailyStats: Codable, Equatable {
    var done = 0
    var snoozed = 0
    var skipped = 0
    var longestBoutSeconds = 0

    static let empty = DailyStats()

    /// "1 snoozed · 1 skipped".
    ///
    /// `done` is deliberately not shown. It counts credited absences as well as routines, and a
    /// day spent away from the desk can run the figure up without the user having done a single
    /// movement, which made it the least trustworthy number in the menu.
    var summary: String {
        "\(snoozed) snoozed · \(skipped) skipped"
    }
}

/// Everything the history keeps, in one Codable blob.
struct HistoryData: Codable, Equatable {
    var completions: [MovementCompletion] = []
    var breakRecords: [BreakRecord] = []
    /// No longer read. The break screen once let an instruction be collapsed for good; the field
    /// stays so a history file still decodes in a build that expects it.
    var collapsedInstructions: Set<String> = []
    var days: [String: DailyStats] = [:]
}

/// What the user has actually done — the input the routine builder needs and the numbers the
/// menu bar shows.
///
/// Foundation-only and saved on every mutation, because a crash five minutes into the afternoon
/// should not cost the morning's record.
final class HistoryStore {
    private(set) var data: HistoryData
    private let store: HistoryPersisting?
    private let calendar: Calendar

    /// How many times a Diff-2 movement must be completed before its Diff-3 counterpart unlocks.
    static let difficultyUnlockThreshold = 5

    /// A history file that will not parse costs the user their record, which is bad — but losing
    /// the app to a crash on every launch afterwards would be worse.
    static func restore(from store: HistoryPersisting) -> HistoryData {
        do {
            return try store.load() ?? HistoryData()
        } catch {
            MovezLog.store.error("history could not be read, starting fresh: \(error.localizedDescription, privacy: .public)")
            return HistoryData()
        }
    }

    init(data: HistoryData = HistoryData(), store: HistoryPersisting? = nil, calendar: Calendar = .current) {
        self.data = data
        self.store = store
        self.calendar = calendar
    }

    convenience init(store: HistoryPersisting, calendar: Calendar = .current) {
        self.init(data: HistoryStore.restore(from: store), store: store, calendar: calendar)
    }

    // MARK: - Recording

    func record(completion: MovementCompletion) {
        data.completions.append(completion)
        save()
    }

    func record(breakRecord: BreakRecord, longestBoutSeconds: Int? = nil) {
        data.breakRecords.append(breakRecord)
        let key = DayKey.key(for: breakRecord.at, calendar: calendar)
        var stats = data.days[key] ?? .empty
        switch breakRecord.outcome {
        case .done, .credited: stats.done += 1
        case .skipped: stats.skipped += 1
        case .snoozed: stats.snoozed += 1
        }
        if let longestBoutSeconds { stats.longestBoutSeconds = max(stats.longestBoutSeconds, longestBoutSeconds) }
        data.days[key] = stats
        save()
    }

    func recordLongestBout(_ seconds: Int, on date: Date) {
        let key = DayKey.key(for: date, calendar: calendar)
        var stats = data.days[key] ?? .empty
        guard seconds > stats.longestBoutSeconds else { return }
        stats.longestBoutSeconds = seconds
        data.days[key] = stats
        save()
    }

    /// Undoes the most recent record of a given kind — the away toast's "I was sitting".
    @discardableResult
    func removeLastBreakRecord(matching outcome: BreakResult) -> Bool {
        guard let index = data.breakRecords.lastIndex(where: { $0.outcome == outcome }) else { return false }
        let record = data.breakRecords.remove(at: index)
        let key = DayKey.key(for: record.at, calendar: calendar)
        if var stats = data.days[key] {
            switch record.outcome {
            case .done, .credited: stats.done = max(0, stats.done - 1)
            case .skipped: stats.skipped = max(0, stats.skipped - 1)
            case .snoozed: stats.snoozed = max(0, stats.snoozed - 1)
            }
            data.days[key] = stats
        }
        save()
        return true
    }

    // MARK: - Reading

    func usedMovementIds(on date: Date) -> Set<String> {
        let key = DayKey.key(for: date, calendar: calendar)
        return Set(
            data.completions
                .filter { DayKey.key(for: $0.at, calendar: calendar) == key }
                .map(\.movementId)
        )
    }

    func completionCount(movementId: String) -> Int {
        data.completions.filter { $0.movementId == movementId }.count
    }

    /// How recently and how often each movement was served in the days before `date`, as the
    /// scores `Recency` turns into selection weights.
    ///
    /// Today is left out: the builders already refuse to repeat a movement inside one day, and
    /// counting today's servings here would only weight down something that cannot be picked.
    func recencyScores(before date: Date) -> [String: Double] {
        let today = calendar.startOfDay(for: date)
        var scores: [String: Double] = [:]
        for completion in data.completions {
            let day = calendar.startOfDay(for: completion.at)
            guard let daysAgo = calendar.dateComponents([.day], from: day, to: today).day else { continue }
            let weight = Recency.weight(daysAgo: daysAgo)
            guard weight > 0 else { continue }
            scores[completion.movementId, default: 0] += weight
        }
        return scores
    }

    func stats(on date: Date) -> DailyStats {
        data.days[DayKey.key(for: date, calendar: calendar)] ?? .empty
    }

    /// Today's breaks, read backwards from the newest and stopped at the first record from
    /// another day. The record grows for as long as the app is used; the answer never depends on
    /// anything before this morning.
    func breaks(on date: Date) -> [BreakRecord] {
        let key = DayKey.key(for: date, calendar: calendar)
        var today: [BreakRecord] = []
        for record in data.breakRecords.reversed() {
            guard DayKey.key(for: record.at, calendar: calendar) == key else { break }
            today.append(record)
        }
        return today.reversed()
    }

    /// Consecutive completed breaks, counting back from the most recent one. A skip resets it; a
    /// snooze is a deferral and does not.
    func streak(on date: Date) -> Int {
        var streak = 0
        for record in breaks(on: date).reversed() where record.outcome.affectsStreak {
            guard record.outcome.countsAsCompleted else { break }
            streak += 1
        }
        return streak
    }

    /// The most recent day with any break recorded — what the off-hours menu shows.
    func lastRecordedDay() -> RecordedDay? {
        guard let record = data.breakRecords.last else { return nil }
        let key = DayKey.key(for: record.at, calendar: calendar)
        return RecordedDay(key: key, date: record.at, stats: data.days[key] ?? .empty)
    }

    /// Which Diff-3 movements the user has earned.
    ///
    /// A Diff-3 movement unlocks once any Diff-2 movement in the same bucket that shares a region
    /// with it has been completed five times — the progression is earned in the same tissue, not
    /// anywhere in the library.
    func unlockedDiff3(library: MovementLibrary) -> Set<String> {
        var counts: [String: Int] = [:]
        for completion in data.completions {
            counts[completion.movementId, default: 0] += 1
        }

        var unlocked: Set<String> = []
        for movement in library.movements where movement.difficulty >= 3 {
            let earned = library.movements.contains { peer in
                peer.difficulty == 2
                    && peer.bucket == movement.bucket
                    && !peer.sharedRegions(with: movement).isEmpty
                    && (counts[peer.id] ?? 0) >= Self.difficultyUnlockThreshold
            }
            if earned { unlocked.insert(movement.id) }
        }
        return unlocked
    }

    private func save() {
        try? store?.save(data)
    }
}
