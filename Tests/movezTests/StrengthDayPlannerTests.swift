import XCTest
@testable import movez

/// The strength day plan: which letter a day is, strength versus end-range, and each break's set
/// order, all read back from history (S22, S6).
final class StrengthDayPlannerTests: XCTestCase {
    private let calendar = Calendar.current
    private lazy var planner = StrengthDayPlanner(calendar: calendar)
    private var records: [BreakRecord] = []

    private let squat = StrengthSetSlot.pattern(.sqt)
    private let push = StrengthSetSlot.pattern(.psh)
    private let hinge = StrengthSetSlot.pattern(.hng)
    private let pull = StrengthSetSlot.pattern(.pul)

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: SchedulerHarness.mondayMorning) ?? SchedulerHarness.mondayMorning
    }

    /// Asks for the next break, then records it as served with `outcome`, the way the coordinator
    /// will. Each break lands an hour after the one before.
    @discardableResult
    private func serve(on dayOffset: Int, perDay: Int, outcome: BreakResult = .done) -> NextFullBreak {
        let at = day(dayOffset).addingTimeInterval(Double(records.filter { sameDay($0.at, day(dayOffset)) }.count) * 3600)
        let plan = planner.next(records: records, strengthBreaksPerDay: perDay, today: at)
        let kind: BreakKind
        if case let .strength(letter, _, _, _) = plan { kind = letter.breakKind } else { kind = .endRange }
        records.append(record(at: at, kind: kind, outcome: outcome))
        return plan
    }

    @discardableResult
    private func serveDay(_ dayOffset: Int, perDay: Int, breaks: Int) -> [NextFullBreak] {
        (0..<breaks).map { _ in serve(on: dayOffset, perDay: perDay) }
    }

    private func record(at: Date, kind: BreakKind?, outcome: BreakResult = .done) -> BreakRecord {
        BreakRecord(
            at: at,
            routineName: BreakRecord.movementBreakName,
            outcome: outcome,
            completedBlocks: 5,
            totalBlocks: 5,
            kind: kind
        )
    }

    private func sameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    private func letter(_ plan: NextFullBreak) -> StrengthDayLetter? {
        if case let .strength(letter, _, _, _) = plan { return letter }
        return nil
    }

    private func orders(_ plans: [NextFullBreak]) -> [[StrengthSetSlot]] {
        plans.compactMap { plan in
            if case let .strength(_, _, _, order) = plan { return order }
            return nil
        }
    }

    // MARK: - Strength versus end-range

    func testAFiveBreakDayAtThreeIsThreeStrengthThenEndRangeWithTheAgreedOrders() {
        let plans = serveDay(0, perDay: 3, breaks: 5)

        XCTAssertEqual(plans, [
            .strength(letter: .dayA, index: 1, of: 3, setOrder: [squat, push, .core]),
            .strength(letter: .dayA, index: 2, of: 3, setOrder: [squat, push, squat]),
            .strength(letter: .dayA, index: 3, of: 3, setOrder: [push, squat, push]),
            .endRange,
            .endRange
        ], "X·Y·Core, X·Y·X, Y·X·Y, then end-range")
    }

    func testOneStrengthBreakADayIsFollowedByEndRange() {
        let plans = serveDay(0, perDay: 1, breaks: 5)
        XCTAssertEqual(plans.prefix(1).compactMap(letter), [.dayA])
        XCTAssertEqual(Array(plans.dropFirst()), Array(repeating: .endRange, count: 4))
        XCTAssertEqual(orders(plans), [[squat, push, .core]])
    }

    func testFourStrengthBreaksADayComeBeforeEndRange() {
        let plans = serveDay(0, perDay: 4, breaks: 5)
        XCTAssertEqual(plans.prefix(4).compactMap(letter).count, 4)
        XCTAssertEqual(plans.last, .endRange)
        XCTAssertEqual(orders(plans), [
            [squat, push, .core],
            [squat, push, squat],
            [push, squat, push],
            [squat, push, squat]
        ])
    }

    func testASkippedOrSnoozedFirstBreakLeavesTheNextOneTheFirstBreak() {
        for outcome in [BreakResult.skipped, .snoozed] {
            records = []
            serve(on: 0, perDay: 3, outcome: outcome)
            let next = serve(on: 0, perDay: 3)
            XCTAssertEqual(
                next,
                .strength(letter: .dayA, index: 1, of: 3, setOrder: [squat, push, .core]),
                "after a \(outcome.rawValue) first break"
            )
        }
    }

    func testAnAbsenceOrAMovementBreakDoesNotCountTowardTheDaysStrengthBreaks() {
        records = [
            record(at: day(0), kind: .strengthA, outcome: .awayReset),
            record(at: day(0).addingTimeInterval(600), kind: nil),
            record(at: day(0).addingTimeInterval(1200), kind: .movement)
        ]
        let next = planner.next(records: records, strengthBreaksPerDay: 1, today: day(0).addingTimeInterval(1800))
        XCTAssertEqual(next, .strength(letter: .dayA, index: 1, of: 1, setOrder: [squat, push, .core]))
    }

    // MARK: - Day letter

    func testTheFirstEverStrengthDayIsA() {
        XCTAssertEqual(planner.letter(records: [], today: day(0)), .dayA)
        let next = planner.next(records: [], strengthBreaksPerDay: 3, today: day(0))
        XCTAssertEqual(letter(next), .dayA)
    }

    func testTheDayAfterAnADayIsBAndTheDayAfterThatIsA() {
        serveDay(0, perDay: 3, breaks: 4)
        let monday = serveDay(1, perDay: 3, breaks: 3)
        XCTAssertEqual(monday.compactMap(letter), [.dayB, .dayB, .dayB])
        XCTAssertEqual(orders(monday).first, [hinge, pull, .core])
        XCTAssertEqual(letter(serve(on: 2, perDay: 3)), .dayA)
    }

    func testAMovementOnlyDayBetweenKeepsTheNextStrengthDayB() {
        serveDay(0, perDay: 3, breaks: 3)
        for hour in 0..<5 {
            records.append(record(at: day(1).addingTimeInterval(Double(hour) * 3600), kind: .movement))
        }
        records.append(record(at: day(2), kind: nil))

        XCTAssertEqual(planner.letter(records: records, today: day(3)), .dayB)
        XCTAssertEqual(letter(serve(on: 3, perDay: 3)), .dayB)
    }

    func testADayOfOnlySkippedStrengthBreaksIsNotAStrengthDay() {
        serveDay(0, perDay: 3, breaks: 3)
        serve(on: 1, perDay: 3, outcome: .skipped)
        serve(on: 1, perDay: 3, outcome: .snoozed)
        XCTAssertEqual(planner.letter(records: records, today: day(2)), .dayB, "Tuesday had no completed strength break")
    }

    func testTheLetterIsFixedOnceTheDaysFirstStrengthBreakCompletes() {
        serveDay(0, perDay: 3, breaks: 2)
        // A record written as B later the same day, which the planner never produces, cannot
        // change a day already fixed as A.
        records.append(record(at: day(0).addingTimeInterval(9000), kind: .strengthB))
        XCTAssertEqual(planner.letter(records: records, today: day(0).addingTimeInterval(10000)), .dayA)
    }

    // MARK: - Lead pattern

    func testATieGoesToThePatternThatLedLessRecentlyToday() {
        // Fourth break of a four-break day: squat led the second, push the third, both stand at
        // four sets, so squat, which led less recently, leads again.
        let plans = serveDay(0, perDay: 4, breaks: 4)
        XCTAssertEqual(orders(plans)[3], [squat, push, squat])
    }

    func testATieWithNoLeadTodayGoesToThePatternThatDidNotLeadLastOnTheLastDayWithThisLetter() {
        // Monday's A day ends with squat leading. Wednesday's second break is a tie with no lead
        // yet today, so push, which led less recently on Monday, leads.
        serveDay(0, perDay: 4, breaks: 4)
        serveDay(1, perDay: 4, breaks: 4)
        let wednesday = serveDay(2, perDay: 4, breaks: 2)
        XCTAssertEqual(wednesday.compactMap(letter), [.dayA, .dayA])
        XCTAssertEqual(orders(wednesday), [[squat, push, .core], [push, squat, push]])
    }

    func testTheLeadRotatesAcrossDaysWithTheSameLetterAtThreeADay() {
        // At three a day an A day's last lead is push, so the next A day's second break leads with
        // squat again: the three-a-day pattern repeats exactly.
        let monday = serveDay(0, perDay: 3, breaks: 3)
        serveDay(1, perDay: 3, breaks: 3)
        let wednesday = serveDay(2, perDay: 3, breaks: 3)
        XCTAssertEqual(orders(wednesday), orders(monday))
    }

    func testTheReplayFallsBackToTheFirstPatternWithNoHistory() {
        let replay = StrengthDayPlanner.replay(letter: .dayB, breaks: 3, priorLead: nil)
        XCTAssertEqual(replay.orders, [[hinge, pull, .core], [hinge, pull, hinge], [pull, hinge, pull]])
        XCTAssertEqual(replay.lastLead, .pul)
    }
}
