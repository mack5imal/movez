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

    func testACreditedAbsenceCountsAsACompletedBreak() {
        let store = HistoryStore()
        record(store, .done, offset: 3600)
        record(store, .credited, offset: 7200)
        XCTAssertEqual(store.streak(on: day), 2)
        XCTAssertEqual(store.stats(on: day).done, 2)
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
        XCTAssertEqual(stats.summary, "1 done · 1 snoozed · 1 skipped")

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

    func testCollapsedInstructionsSurviveARelaunch() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("movez-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = FileHistoryStore(url: directory.appendingPathComponent("history.json"))
        let store = HistoryStore(store: file)
        store.setCollapsed("STR-11", true)
        XCTAssertTrue(store.isCollapsed("STR-11"))

        let reloaded = HistoryStore(store: FileHistoryStore(url: file.url))
        XCTAssertTrue(reloaded.isCollapsed("STR-11"))
        XCTAssertFalse(reloaded.isCollapsed("STR-12"))

        let permissions = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions]
        XCTAssertEqual((permissions as? NSNumber)?.intValue, 0o600)

        reloaded.setCollapsed("STR-11", false)
        XCTAssertFalse(HistoryStore(store: FileHistoryStore(url: file.url)).isCollapsed("STR-11"))
    }

    func testEveryMutationWritesToDisk() throws {
        let file = InMemoryHistoryStore()
        let store = HistoryStore(store: file)
        store.record(completion: MovementCompletion(movementId: "FLX-01", at: day, seconds: 60, routineId: nil))
        record(store, .done, offset: 60)
        store.setCollapsed("FLX-01", true)
        store.recordLongestBout(600, on: day)
        XCTAssertEqual(file.saveCount, 4)
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
