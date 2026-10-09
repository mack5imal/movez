import AppKit
import XCTest
@testable import movez

@MainActor
final class PanelViewModelTests: XCTestCase {
    private let library = RoutineTestSupport.library
    private let start = SchedulerHarness.mondayMorning

    // MARK: - Fixtures

    private func headsUp(
        clock: ManualClock,
        snoozesLeft: Int = 2,
        deferred: PanelViewModel.DeferredInfo? = nil
    ) -> PanelViewModel {
        let model = PanelViewModel(phase: .headsUp, clock: clock, startedAt: clock.now, totalSeconds: 60)
        model.blockCount = 5
        model.breakMinutes = 5
        model.skipsToday = 1
        model.snoozesLeft = snoozesLeft
        model.deferred = deferred
        return model
    }

    private func microBreak(id: String = "CIR-06") -> MicroBreak {
        guard let movement = library.movement(id: id) else {
            fatalError("the bundled library has no \(id)")
        }
        return MicroBreak(
            id: UUID(),
            blocks: [RoutineBlock(movement: movement, seconds: 60)]
        )
    }

    private func microCountIn(clock: ManualClock, remaining: TimeInterval = 21) -> PanelViewModel {
        let model = PanelViewModel(
            phase: .microCountIn,
            clock: clock,
            startedAt: clock.now.addingTimeInterval(remaining - 30),
            totalSeconds: 30
        )
        model.micro = microBreak()
        model.microSeconds = 60
        return model
    }

    private func toast(clock: ManualClock, kind: ToastInfo.Kind, awaySeconds: Int) -> PanelViewModel {
        let model = PanelViewModel(
            phase: .toast,
            clock: clock,
            startedAt: clock.now,
            totalSeconds: ToastInfo.defaultSecondsOnScreen
        )
        model.toast = ToastInfo(
            kind: kind,
            awaySeconds: awaySeconds,
            nextBreakAt: nextBreakAtTwoPastTwo,
            reversal: kind == .creditedFullBreak ? .wasSittingAfterFullCredit : .wasSittingAfterMicroCredit
        )
        return model
    }

    private var nextBreakAtTwoPastTwo: Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: start)
        components.hour = 14
        components.minute = 2
        return Calendar.current.date(from: components) ?? start
    }

    // MARK: - Heads-up

    func testHeadsUpCopyMatchesTheHandoff() {
        let model = headsUp(clock: ManualClock(now: start))
        XCTAssertEqual(model.eyebrow, "MOVEMENT BREAK")
        XCTAssertEqual(model.title, "Movement break in a minute")
        XCTAssertEqual(model.body, "Five minutes, five movements.")
        XCTAssertEqual(model.skipLabel, "Skip · 1 today")
    }

    func testNumberWordsAreSpelledOutAndAgreeInNumber() {
        XCTAssertEqual(PanelViewModel.headsUpBody(minutes: 5, movements: 4), "Five minutes, four movements.")
        XCTAssertEqual(PanelViewModel.headsUpBody(minutes: 1, movements: 1), "One minute, one movement.")
        XCTAssertEqual(PanelViewModel.headsUpBody(minutes: 3, movements: 5), "Three minutes, five movements.")
    }

    /// The minute counts down to the break rather than through it, so it wears a minus, exactly as
    /// the micro-break's count-in does.
    func testTheDiscDrainsOverTheHeadsUpMinute() {
        let clock = ManualClock(now: start)
        let model = headsUp(clock: clock)

        XCTAssertEqual(model.remaining, 60)
        XCTAssertEqual(model.progress, 1, accuracy: 0.001)
        XCTAssertEqual(model.discNumerals, "−1:00")

        clock.advance(30)
        model.tick()
        XCTAssertEqual(model.remaining, 30)
        XCTAssertEqual(model.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(model.discNumerals, "−0:30")

        clock.advance(30)
        model.tick()
        XCTAssertEqual(model.remaining, 0)
        XCTAssertEqual(model.progress, 0, accuracy: 0.001)
        XCTAssertEqual(model.discNumerals, "−0:00")
    }

    func testStartNowGoesToTheCoordinator() {
        let model = headsUp(clock: ManualClock(now: start))
        var started = 0
        model.actions.startNow = { started += 1 }
        model.startNow()
        XCTAssertEqual(started, 1)
    }

    func testSnoozeSpendsAnAllowanceAndThenDisappears() {
        let model = headsUp(clock: ManualClock(now: start), snoozesLeft: 1)
        var snoozes = 0
        model.actions.snooze = { snoozes += 1 }

        XCTAssertTrue(model.showSnooze)
        model.snooze()
        XCTAssertEqual(snoozes, 1)
        XCTAssertEqual(model.snoozesLeft, 0)
        XCTAssertFalse(model.showSnooze, "a spent allowance removes the button rather than disabling it")

        model.snooze()
        XCTAssertEqual(snoozes, 1, "there is nothing left to spend")
    }

    func testSkipIsInertForTheFirstThreeSeconds() {
        let clock = ManualClock(now: start)
        let model = headsUp(clock: clock)
        var skips = 0
        model.actions.skip = { skips += 1 }

        XCTAssertFalse(model.skipEnabled)
        model.skip()
        XCTAssertEqual(skips, 0)

        clock.advance(3)
        model.tick()
        XCTAssertTrue(model.skipEnabled)
        model.skip()
        XCTAssertEqual(skips, 1)
    }

    // MARK: - The deferred variant

    func testTheDeferredBadgeNamesTheSignalThatHeldTheBreakBack() {
        let deferred = PanelViewModel.DeferredInfo(sittingFor: 5_700, reason: .microphone)
        let model = headsUp(clock: ManualClock(now: start), snoozesLeft: 0, deferred: deferred)

        XCTAssertEqual(model.deferredBadge, "Sitting for 1 h 35 m · break waited for your call")
        XCTAssertFalse(model.showSnooze, "a break that waited half an hour has already spent its one snooze")
        XCTAssertEqual(model.panelWidth, Tokens.Metric.panelWidthDeferred)
    }

    func testEverySuppressionReasonHasItsOwnPhrase() {
        let clock = ManualClock(now: start)
        let phrases = SuppressionReason.allCases.map { reason -> String? in
            headsUp(clock: clock, deferred: .init(sittingFor: 2_100, reason: reason)).deferredBadge
        }
        XCTAssertEqual(phrases, [
            "Sitting for 35 m · break waited for your call",
            "Sitting for 35 m · break waited for your screen share",
            "Sitting for 35 m · break waited for your fullscreen app"
        ])
    }

    func testAnUndeferredPanelHasNoBadgeAndTheNarrowerWidth() {
        let model = headsUp(clock: ManualClock(now: start))
        XCTAssertNil(model.deferredBadge)
        XCTAssertEqual(model.panelWidth, Tokens.Metric.panelWidth)
    }

    // MARK: - Micro-break count-in

    func testTheCountInCountsDownInWordsAndNumerals() {
        let clock = ManualClock(now: start)
        let model = microCountIn(clock: clock)

        XCTAssertEqual(model.eyebrow, "MICRO-BREAK · SHOULDERS")
        XCTAssertEqual(model.title, "Arm circles in a moment")
        XCTAssertEqual(model.discNumerals, "−0:21")
        XCTAssertEqual(model.body, "One minute, standing. Starts in 21 seconds.")

        clock.advance(20)
        model.tick()
        XCTAssertEqual(model.discNumerals, "−0:01")
        XCTAssertEqual(model.body, "One minute, standing. Starts in 1 second.")
    }

    func testAChairOnlyMicroBreakIsDoneSeated() throws {
        let movement = try XCTUnwrap(library.movement(id: "EYE-04"), "the bundled library has EYE-04 Palming")
        XCTAssertEqual(movement.settings, [.chair])

        let clock = ManualClock(now: start)
        let model = microCountIn(clock: clock)
        model.micro = MicroBreak(
            id: UUID(),
            blocks: [RoutineBlock(movement: movement, seconds: 60)]
        )
        XCTAssertTrue(model.body.contains("seated"), model.body)
    }

    func testTheCountInBecomesTheMovementAtZero() {
        let clock = ManualClock(now: start)
        let model = microCountIn(clock: clock)

        clock.advance(21)
        model.tick()

        XCTAssertEqual(model.phase, .microRunning)
        XCTAssertEqual(model.title, "Arm circles")
        XCTAssertEqual(model.body, library.movement(id: "CIR-06")?.instructions)
        XCTAssertEqual(model.remaining, 60)
        XCTAssertEqual(model.discNumerals, "1:00")
    }

    func testTheMinuteEndsExactlyOnce() {
        let clock = ManualClock(now: start)
        let model = microCountIn(clock: clock)
        var ended = 0
        model.actions.microEnded = { ended += 1 }

        clock.advance(21)
        model.tick()
        XCTAssertEqual(ended, 0, "the movement has only just started")

        clock.advance(60)
        model.tick()
        XCTAssertEqual(model.discNumerals, "0:00")
        XCTAssertEqual(ended, 1)

        clock.advance(5)
        model.tick()
        XCTAssertEqual(ended, 1, "a finished micro-break does not keep reporting itself")
    }

    func testTheSecondMicroSnoozeIsASkip() {
        let clock = ManualClock(now: start)
        let model = microCountIn(clock: clock)
        var snoozes = 0
        var skips = 0
        model.actions.microSnooze = { snoozes += 1 }
        model.actions.microSkip = { skips += 1 }

        model.snooze()
        XCTAssertEqual(snoozes, 1)
        XCTAssertEqual(skips, 0)

        model.snooze()
        XCTAssertEqual(snoozes, 1)
        XCTAssertEqual(skips, 1, "one snooze is the allowance; asking again is a skip")
    }

    func testAMicroBreakSkipCarriesNoCount() {
        let clock = ManualClock(now: start)
        let model = microCountIn(clock: clock)
        XCTAssertEqual(model.skipLabel, "Skip")
        XCTAssertTrue(model.showSnooze)
    }

    // MARK: - The away toast

    func testToastCopyForBothCredits() {
        let clock = ManualClock(now: start)
        XCTAssertEqual(
            toast(clock: clock, kind: .creditedFullBreak, awaySeconds: 420).toastTitle,
            "Away 7 min · counted as your break"
        )
        XCTAssertEqual(
            toast(clock: clock, kind: .creditedMicroBreak, awaySeconds: 240).toastTitle,
            "Away 4 min · counted as a micro-break"
        )
        XCTAssertEqual(
            toast(clock: clock, kind: .creditedFullBreak, awaySeconds: 420).toastSubtitle,
            "Next break at 14:02"
        )
    }

    func testTheHairlineShrinksOverFifteenSeconds() {
        let clock = ManualClock(now: start)
        let model = toast(clock: clock, kind: .creditedFullBreak, awaySeconds: 420)
        XCTAssertEqual(ToastInfo.defaultSecondsOnScreen, 15)

        XCTAssertEqual(model.progress, 1, accuracy: 0.001)
        clock.advance(7.5)
        model.tick()
        XCTAssertEqual(model.progress, 0.5, accuracy: 0.001)
        clock.advance(7.5)
        model.tick()
        XCTAssertEqual(model.progress, 0, accuracy: 0.001)
    }

    func testTheToastDismissesItselfWhenItRunsOut() {
        let clock = ManualClock(now: start)
        let model = toast(clock: clock, kind: .creditedFullBreak, awaySeconds: 420)
        var dismissed = 0
        model.actions.dismiss = { dismissed += 1 }

        clock.advance(14)
        model.tick()
        XCTAssertEqual(dismissed, 0, "six seconds was too short to reach; fifteen is not up yet")
        clock.advance(1)
        model.tick()
        XCTAssertEqual(dismissed, 1)
    }

    func testDismissTakesTheToastAwayAndKeepsTheCredit() {
        let clock = ManualClock(now: start)
        let model = toast(clock: clock, kind: .creditedFullBreak, awaySeconds: 420)
        var reversed = 0
        var dismissed = 0
        model.actions.reverseToast = { reversed += 1 }
        model.actions.dismiss = { dismissed += 1 }

        model.dismissToast()
        XCTAssertEqual(dismissed, 1)
        XCTAssertEqual(reversed, 0, "dismissing is not reversing")
    }

    func testIWasSittingReversesTheCreditAndTakesTheToastAway() {
        let clock = ManualClock(now: start)
        let model = toast(clock: clock, kind: .creditedFullBreak, awaySeconds: 420)
        var reversed = 0
        var dismissed = 0
        model.actions.reverseToast = { reversed += 1 }
        model.actions.dismiss = { dismissed += 1 }

        model.reverse()
        XCTAssertEqual(reversed, 1)
        XCTAssertEqual(dismissed, 1)
    }

    // MARK: - Placement

    /// A 1440×900 display with a 25 pt menu bar and a 70 pt dock, which is what `visibleFrame`
    /// looks like on an ordinary Mac.
    private let visible = NSRect(x: 0, y: 70, width: 1440, height: 805)

    func testPanelsSitTopCentreUnderTheMenuBar() {
        let frame = PanelWindowController.panelFrame(shell: CGSize(width: 400, height: 140), visible: visible)
        XCTAssertEqual(frame.midX, visible.midX, accuracy: 1)
        XCTAssertEqual(frame.maxY, visible.maxY - PanelWindowController.topInset, accuracy: 1)
        XCTAssertEqual(PanelWindowController.topInset, 12)
    }

    func testTheToastSitsTwentyPointsOffTheBottomRightCorner() {
        let frame = PanelWindowController.toastFrame(shell: CGSize(width: 380, height: 64), visible: visible)
        XCTAssertEqual(visible.maxX - frame.maxX, 20, accuracy: 1)
        XCTAssertEqual(frame.minY - visible.minY, 20, accuracy: 1)
    }

    func testTheShellFrameIsTheWindowFrameWithoutItsShadowMargin() {
        let shell = NSRect(x: 100, y: 200, width: 400, height: 140)
        let window = PanelWindowController.windowFrame(forShell: shell)
        XCTAssertEqual(window.insetBy(dx: PanelWindowController.shadowMargin, dy: PanelWindowController.shadowMargin), shell)
    }
}
