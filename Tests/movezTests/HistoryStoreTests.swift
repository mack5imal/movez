import XCTest
@testable import movez

final class HistoryStoreTests: XCTestCase {
    private let day = SchedulerHarness.mondayMorning

    private func record(_ store: HistoryStore, _ outcome: BreakResult, offset: TimeInterval) {
        store.record(breakRecord: BreakRecord(
            at: day.addingTimeInterval(offset),
            routineName: "Hip reset",
            outcome: outcome,
            completedBlocks: 4,
            totalBlocks: 4
        ))
    }

    func testStreakCountsConsecutiveCompletions() {
        let store = HistoryStore()
        XCTAssertEqual(store.streak(on: day), 0)

        record(store, .done, offset: 3600)
        record(store, .done, offset: 7200)
        XCTAssertEqual(store.streak(on: day), 2)

        record(store, .skipped, offset: 10_800)
        XCTAssertEqual(store.streak(on: day), 0, "a skip resets the streak")

        record(store, .done, offset: 14_400)
        XCTAssertEqual(store.streak(on: day), 1)
    }

    func testSnoozeNeitherBreaksNorBuildsTheStreak() {
        let store = HistoryStore()
        record(store, .done, offset: 3600)
        record(store, .snoozed, offset: 5400)
        record(store, .done, offset: 7200)
        XCTAssertEqual(store.streak(on: day), 2, "a snooze is a deferral, not a failure")
        XCTAssertEqual(store.stats(on: day).snoozed, 1)
    }

    /// Written by an earlier build. It keeps counting, so days already recorded keep their numbers.
    func testACreditedAbsenceFromBeforeStillCountsAsACompletedBreak() {
        let store = HistoryStore()
        record(store, .done, offset: 3600)
        record(store, .credited, offset: 7200)
        XCTAssertEqual(store.streak(on: day), 2)
        XCTAssertEqual(store.stats(on: day).done, 2)
    }

    /// An absence is logged and counts for nothing: not done, not skipped, and it neither adds to
    /// nor breaks the streak.
    func testAnAbsenceNeitherCountsNorBreaksTheStreak() {
        let store = HistoryStore()
        record(store, .done, offset: 3600)
        record(store, .awayReset, offset: 5400)
        record(store, .done, offset: 7200)
        record(store, .awayPaused, offset: 9000)
        XCTAssertEqual(store.streak(on: day), 2)
        let stats = store.stats(on: day)
        XCTAssertEqual([stats.done, stats.skipped, stats.snoozed], [2, 0, 0])
        XCTAssertEqual(store.data.breakRecords.count, 4, "both absences are in the record")

        XCTAssertTrue(store.removeLastBreakRecord(matching: .awayPaused))
        XCTAssertEqual(store.stats(on: day).done, 2, "taking one back moves nothing either")
    }

    func testADayOfNothingButAbsencesIsNotTheLastRecordedDay() {
        let store = HistoryStore()
        record(store, .done, offset: 3600)
        store.record(breakRecord: BreakRecord(
            at: day.addingTimeInterval(86_400 + 3600),
            routineName: "Away 7 min",
            outcome: .awayReset,
            completedBlocks: 0,
            totalBlocks: 0
        ))
        XCTAssertEqual(store.lastRecordedDay()?.key, DayKey.key(for: day, calendar: .current))
    }

    func testDailyStatsAndLongestBout() {
        let store = HistoryStore()
        record(store, .done, offset: 3600)
        record(store, .skipped, offset: 7200)
        record(store, .snoozed, offset: 10_800)
        store.recordLongestBout(4_320, on: day)
        store.recordLongestBout(1_200, on: day)

        let stats = store.stats(on: day)
        XCTAssertEqual(stats.done, 1)
        XCTAssertEqual(stats.skipped, 1)
        XCTAssertEqual(stats.snoozed, 1)
        XCTAssertEqual(stats.longestBoutSeconds, 4_320, "the longest bout only ever grows")
        XCTAssertEqual(stats.summary, "1 snoozed · 1 skipped")

        let tomorrow = day.addingTimeInterval(24 * 3600)
        XCTAssertEqual(store.stats(on: tomorrow), .empty)
    }

    func testDifficultyThreeUnlocksAtFiveCompletionsOfAMatchingPeer() {
        let library = RoutineTestSupport.library
        let store = HistoryStore()
        XCTAssertFalse(store.unlockedDiff3(library: library).contains("STR-29"))

        // STR-14 is the Diff 2 side plank; it shares L-spine/Core with the Diff 3 Copenhagen.
        for index in 0..<4 {
            store.record(completion: MovementCompletion(
                movementId: "STR-14",
                at: day.addingTimeInterval(TimeInterval(index * 3600)),
                seconds: 60,
                routineId: nil
            ))
        }
        XCTAssertFalse(store.unlockedDiff3(library: library).contains("STR-29"), "four is not enough")

        store.record(completion: MovementCompletion(movementId: "STR-14", at: day, seconds: 60, routineId: nil))
        XCTAssertTrue(store.unlockedDiff3(library: library).contains("STR-29"))
        XCTAssertFalse(
            store.unlockedDiff3(library: library).contains("BAL-15"),
            "progress in one bucket does not unlock another"
        )
    }

    func testUsedMovementIdsAreScopedToTheDay() {
        let store = HistoryStore()
        store.record(completion: MovementCompletion(movementId: "FLX-01", at: day, seconds: 60, routineId: nil))
        store.record(completion: MovementCompletion(
            movementId: "CIR-01",
            at: day.addingTimeInterval(24 * 3600),
            seconds: 60,
            routineId: nil
        ))
        XCTAssertEqual(store.usedMovementIds(on: day), ["FLX-01"])
        XCTAssertEqual(store.completionCount(movementId: "FLX-01"), 1)
    }

    func testTheHistoryFileSurvivesARelaunchAndIsPrivate() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("movez-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = FileHistoryStore(url: directory.appendingPathComponent("history.json"))
        let store = HistoryStore(store: file)
        store.record(completion: MovementCompletion(movementId: "STR-11", at: day, seconds: 60, routineId: nil))

        let reloaded = HistoryStore(store: FileHistoryStore(url: file.url))
        XCTAssertEqual(reloaded.completionCount(movementId: "STR-11"), 1)
        XCTAssertEqual(reloaded.completionCount(movementId: "STR-12"), 0)

        let permissions = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions]
        XCTAssertEqual((permissions as? NSNumber)?.intValue, 0o600)
    }

    /// Files written while the break screen could collapse an instruction still load.
    func testAFileWithCollapsedInstructionsStillLoads() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("movez-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("history.json")
        let legacy = """
            {"completions":[],"breakRecords":[],"collapsedInstructions":["STR-11"],
             "days":{"2026-09-07":{"done":3,"skipped":0,"snoozed":1,"longestBoutSeconds":600}}}
            """
        try Data(legacy.utf8).write(to: url)

        let store = HistoryStore(store: FileHistoryStore(url: url))
        XCTAssertEqual(store.data.days["2026-09-07"]?.done, 3, "the file loaded rather than starting fresh")
    }

    func testEveryMutationWritesToDisk() throws {
        let file = InMemoryHistoryStore()
        let store = HistoryStore(store: file)
        store.record(completion: MovementCompletion(movementId: "FLX-01", at: day, seconds: 60, routineId: nil))
        record(store, .done, offset: 60)
        store.recordLongestBout(600, on: day)
        XCTAssertEqual(file.saveCount, 3)
    }

    func testReversingACreditedBreakUndoesTheCount() {
        let store = HistoryStore()
        record(store, .done, offset: 3600)
        record(store, .credited, offset: 7200)
        XCTAssertEqual(store.stats(on: day).done, 2)

        XCTAssertTrue(store.removeLastBreakRecord(matching: .credited))
        XCTAssertEqual(store.stats(on: day).done, 1)
        XCTAssertEqual(store.streak(on: day), 1)
        XCTAssertFalse(store.removeLastBreakRecord(matching: .credited))
    }

    func testLastRecordedDay() {
        let store = HistoryStore()
        XCTAssertNil(store.lastRecordedDay())
        record(store, .done, offset: 3600)
        XCTAssertEqual(store.lastRecordedDay()?.stats.done, 1)
    }
}
