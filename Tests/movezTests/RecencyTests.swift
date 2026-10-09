import XCTest
@testable import movez

/// The three-day memory that stops the builders serving the same movements every day.
final class RecencyTests: XCTestCase {
    private let day: TimeInterval = 24 * 3600

    func testYesterdayCountsMostAndTheFourthDayIsForgotten() {
        XCTAssertEqual(Recency.weight(daysAgo: 1), 1, accuracy: 0.001)
        XCTAssertEqual(Recency.weight(daysAgo: 2), 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(Recency.weight(daysAgo: 3), 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(Recency.weight(daysAgo: 4), 0)
        XCTAssertEqual(Recency.weight(daysAgo: 0), 0, "today is handled by the no-repeats rule")
        XCTAssertEqual(Recency.weight(daysAgo: -1), 0)
    }

    func testTheMultiplierFallsWithTheScoreAndNeverReachesZero() {
        XCTAssertEqual(Recency.multiplier(score: 0), 1, accuracy: 0.001)
        XCTAssertEqual(Recency.multiplier(score: 1), 1.0 / 3.0, accuracy: 0.001, "once yesterday")
        XCTAssertLessThan(Recency.multiplier(score: 3), Recency.multiplier(score: 1))
        XCTAssertGreaterThan(Recency.multiplier(score: 50), 0, "a pool that has all been served still has to serve")
    }

    func testScoresAreReadOutOfHistoryByCalendarDay() {
        let today = SchedulerHarness.mondayMorning
        let history = HistoryStore()
        for (id, daysAgo) in [("FLX-01", 1.0), ("FLX-02", 2.0), ("FLX-03", 3.0), ("FLX-04", 5.0)] {
            history.record(completion: MovementCompletion(
                movementId: id,
                at: today.addingTimeInterval(-daysAgo * day),
                seconds: 60,
                routineId: UUID()
            ))
        }
        history.record(completion: MovementCompletion(movementId: "FLX-01", at: today, seconds: 60, routineId: UUID()))

        let scores = history.recencyScores(before: today)
        XCTAssertEqual(scores["FLX-01"] ?? 0, 1, accuracy: 0.001, "today's serving is not counted")
        XCTAssertEqual(scores["FLX-02"] ?? 0, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(scores["FLX-03"] ?? 0, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertNil(scores["FLX-04"], "five days ago is outside the horizon")
    }

    func testDoingTheSameMovementTwiceInTheHorizonWeighsItDownFurther() {
        let today = SchedulerHarness.mondayMorning
        let history = HistoryStore()
        for daysAgo in [1.0, 2.0] {
            history.record(completion: MovementCompletion(
                movementId: "CIR-01",
                at: today.addingTimeInterval(-daysAgo * day),
                seconds: 60,
                routineId: UUID()
            ))
        }

        let score = history.recencyScores(before: today)["CIR-01"] ?? 0
        XCTAssertEqual(score, 1 + 2.0 / 3.0, accuracy: 0.001)
        XCTAssertLessThan(Recency.multiplier(score: score), Recency.multiplier(score: 1))
    }
}
