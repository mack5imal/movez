import AppKit
import XCTest
@testable import movez

@MainActor
final class MenuBarViewModelTests: XCTestCase {
    /// Saturday 12 September 2026 at 10:41 — outside the standard working week.
    private let saturday = date(month: 9, day: 12, hour: 10, minute: 41)

    private static func date(month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 1_767_225_600)
    }

    private func date(month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        Self.date(month: month, day: day, hour: hour, minute: minute)
    }

    private func harness(
        workingHours: WorkingHours = .alwaysOn,
        startAt: Date = SchedulerHarness.mondayMorning
    ) -> CoordinatorHarness {
        CoordinatorHarness(workingHours: workingHours, startAt: startAt)
    }

    private func viewModel(_ harness: CoordinatorHarness) -> MenuBarViewModel {
        MenuBarViewModel(coordinator: harness.coordinator)
    }

    // MARK: - Sitting

    func testSittingShowsTheCountdownAndTheRoutineItIsCountingTowards() {
        let harness = harness()
        harness.run(seconds: 23 * 60)
        let menu = viewModel(harness)

        XCTAssertEqual(menu.state.mode, .sitting)
        XCTAssertEqual(menu.state.minutesRemaining, 32)
        XCTAssertEqual(menu.state.title, "Next break in 32 min")
        XCTAssertEqual(menu.state.subtitle, harness.coordinator.nextRoutinePreview?.subtitle)
        XCTAssertFalse(menu.state.subtitle.isEmpty)
        XCTAssertEqual(menu.state.elapsedFraction, 23.0 / 55, accuracy: 0.01)
        XCTAssertEqual(menu.labelText, "32m")
    }

    /// The menu must advertise the routine the overlay will actually serve.
    func testTheSubtitleIsTheRoutineTheBreakThenRuns() throws {
        let harness = harness()
        let menu = viewModel(harness)
        let advertised = menu.state.subtitle

        harness.coordinator.takeBreakNow()
        let served = try XCTUnwrap(harness.coordinator.currentBreak?.routine)
        XCTAssertEqual(advertised, served.subtitle)
    }

    func testTheDiscShowsWhatIsLeftAndTheIconWhatHasGone() {
        var state = MenuBarState()
        state.mode = .sitting
        state.elapsedFraction = 0.42
        XCTAssertEqual(state.discProgress, 0.58, accuracy: 0.001)
        XCTAssertEqual(state.discMode, .full)
    }

    // MARK: - The icon

    func testTheIconIsATemplateAtEveryMode() {
        for mode in [MenuBarState.Mode.sitting, .paused, .offHours] {
            let image = MenuBarIcon.image(mode: mode, fraction: 0.5)
            XCTAssertTrue(image.isTemplate, mode.rawValue)
            XCTAssertEqual(image.size, NSSize(width: 12, height: 12), mode.rawValue)
        }
    }

    func testOffHoursDrawsTheRingQuieterAndSaysNothing() {
        XCTAssertEqual(MenuBarIcon.ringAlpha(for: .offHours), 0.55, accuracy: 0.001)

        var state = MenuBarState()
        state.mode = .offHours
        XCTAssertEqual(state.labelText, "")
        XCTAssertEqual(state.discMode, .empty)
    }

    func testPausedWearsTheGlyphInTheTextNotTheIcon() {
        var state = MenuBarState()
        state.mode = .paused
        state.minutesRemaining = 42
        XCTAssertEqual(state.labelText, "‖ 42m")
        XCTAssertEqual(state.discMode, .dashed)
    }

    func testABreakOnScreenSaysSoInsteadOfCountingDown() {
        var state = MenuBarState()
        state.minutesRemaining = 32
        state.isBreaking = true
        state.breakLabel = "break"
        XCTAssertEqual(state.labelText, "break")
        state.breakLabel = "micro"
        XCTAssertEqual(state.labelText, "micro")
    }

    // MARK: - Actions

    func testTakeBreakNowGoesStraightToTheBreak() {
        let harness = harness()
        viewModel(harness).takeBreakNow()
        XCTAssertEqual(harness.state.name, "full_break", "no heads-up when the user asked for it")
    }

    func testMakeDueMovesTheNextBreak() {
        let harness = harness()
        let expected = harness.now.addingTimeInterval(10 * 60)
        viewModel(harness).makeDue(10)

        let due = harness.scheduler.snapshot.nextFullDueAt ?? .distantPast
        XCTAssertEqual(due.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
    }

    func testPauseResumeAndExtend() {
        let harness = harness()
        let menu = viewModel(harness)
        harness.run(seconds: 32 * 60)

        menu.pause(.thirtyMinutes)
        XCTAssertEqual(harness.state.name, "paused")
        XCTAssertEqual(menu.state.mode, .paused)
        XCTAssertEqual(menu.state.minutesRemaining, 30)
        XCTAssertEqual(menu.state.title, "Paused · 30 min left")
        XCTAssertTrue(menu.state.subtitle.hasPrefix("Countdown resumes at "), menu.state.subtitle)
        XCTAssertTrue(menu.state.subtitle.hasSuffix("with 23 min left"), menu.state.subtitle)

        menu.extendPause(.fifteenMinutes)
        XCTAssertEqual(menu.state.minutesRemaining, 45)

        menu.resume()
        XCTAssertEqual(harness.state.name, "sitting")
        XCTAssertEqual(menu.state.mode, .sitting)
        XCTAssertEqual(menu.state.minutesRemaining, 23, "the pause handed the countdown back untouched")
    }

    func testPausedTakeABreakNowIsQuietButNotDisabled() {
        let harness = harness()
        let menu = viewModel(harness)
        menu.pause(.oneHour)
        XCTAssertTrue(menu.state.takeBreakDimmed)

        menu.takeBreakNow()
        XCTAssertEqual(harness.state.name, "full_break", "a break asked for by hand ends the pause")
    }

    func testSessionsStartAndEndOutsideWorkingHours() {
        let harness = harness(workingHours: .standard, startAt: saturday)
        harness.run(seconds: 4)
        let menu = viewModel(harness)
        XCTAssertEqual(menu.state.mode, .offHours)

        menu.startSession()
        XCTAssertEqual(harness.state.name, "sitting")
        XCTAssertEqual(menu.state.mode, .sitting)
        XCTAssertTrue(menu.state.isAdHocSession)

        menu.endSession()
        XCTAssertEqual(harness.state.name, "off_hours")
        XCTAssertEqual(menu.state.mode, .offHours)
        XCTAssertFalse(menu.state.isAdHocSession)
    }

    func testExpandingOneRowCollapsesTheOther() {
        let menu = viewModel(harness())
        menu.togglePauseOptions()
        XCTAssertTrue(menu.state.pauseExpanded)

        menu.toggleExtendOptions()
        XCTAssertFalse(menu.state.pauseExpanded)
        XCTAssertTrue(menu.state.extendExpanded)
    }

    // MARK: - Off hours

    func testOffHoursSaysWhenBreaksComeBackAndShowsTheLastWorkingDay() {
        let harness = harness(workingHours: .standard, startAt: saturday)
        harness.history.record(
            breakRecord: BreakRecord(
                at: date(month: 9, day: 11, hour: 16),
                routineName: "Hip reset",
                outcome: .done,
                completedBlocks: 4,
                totalBlocks: 4
            ),
            longestBoutSeconds: 95 * 60
        )
        harness.run(seconds: 4)
        let menu = viewModel(harness)

        XCTAssertEqual(menu.state.title, "Off hours")
        XCTAssertEqual(menu.state.subtitle, "Breaks resume Monday at 9:00")
        XCTAssertEqual(menu.state.stats, "Friday · 0 snoozed · 0 skipped")
        XCTAssertEqual(menu.state.longestBout, "Longest sitting bout 1 h 35 m")
    }

    func testTodayAndTomorrowReadBetterThanTheirDayNames() {
        let friday = date(month: 9, day: 11, hour: 20)
        XCTAssertEqual(
            MenuBarState.offHoursSubtitle(nextStart: date(month: 9, day: 11, hour: 21), now: friday),
            "Breaks resume today at 21:00"
        )
        XCTAssertEqual(
            MenuBarState.offHoursSubtitle(nextStart: date(month: 9, day: 12, hour: 9), now: friday),
            "Breaks resume tomorrow at 9:00"
        )
        XCTAssertEqual(
            MenuBarState.offHoursSubtitle(nextStart: date(month: 9, day: 14, hour: 9), now: friday),
            "Breaks resume Monday at 9:00"
        )
    }

    // MARK: - Away

    /// The bug this covers: an absence outlives the countdown, so the menu counted down to zero
    /// and sat there claiming a break was due to someone who was not at the desk.
    func testAwayShowsHowLongTheUserHasBeenGoneRatherThanAStaleCountdown() {
        let harness = harness()
        harness.run(seconds: 50 * 60)
        harness.coordinator.inject(.idle(seconds: 6 * 60))
        harness.run(seconds: 20 * 60)
        let menu = viewModel(harness)

        XCTAssertEqual(menu.state.mode, .away)
        XCTAssertEqual(menu.state.minutesRemaining, 26, "six minutes idle plus twenty more away")
        XCTAssertEqual(menu.state.title, "Away 26 min")
        XCTAssertEqual(menu.state.subtitle, "Your countdown is on hold")
        XCTAssertEqual(menu.labelText, "—")
        XCTAssertEqual(menu.state.discMode, .empty)
        XCTAssertEqual(menu.state.discNumerals, "")
        XCTAssertFalse(menu.state.title.contains("Next break"), "the countdown is not running")
    }

    /// The quiet minute after a wake still belongs to the absence, which is when the user is most
    /// likely to be looking at the menu.
    func testTheQuietMinuteAfterAWakeStillReadsAsAway() {
        let harness = harness()
        harness.run(seconds: 10 * 60)
        harness.coordinator.inject(.sleep)
        harness.clock.advance(68 * 60)
        harness.coordinator.inject(.wake(gapSeconds: 68 * 60))
        harness.run(seconds: 20)
        let menu = viewModel(harness)

        XCTAssertEqual(menu.state.mode, .away)
        XCTAssertEqual(menu.state.title, "Away 68 min", "frozen at the length of the absence")

        // The quiet minute ends, standby resolves the absence, and the countdown starts again.
        harness.run(seconds: 60)
        menu.refresh()
        XCTAssertEqual(menu.state.mode, .sitting)
        XCTAssertEqual(menu.state.minutesRemaining, 55)
    }

    func testAwayTitleSwitchesToHoursWhenMinutesStopReading() {
        XCTAssertEqual(MenuBarState.awayTitle(seconds: 7 * 60), "Away 7 min")
        XCTAssertEqual(MenuBarState.awayTitle(seconds: 119 * 60), "Away 119 min")
        XCTAssertEqual(MenuBarState.awayTitle(seconds: 200 * 60), "Away 3 h 20 m")
        XCTAssertEqual(MenuBarState.title(mode: .away, minutesRemaining: 68), "Away 68 min")
    }

    // MARK: - Stats strings

    func testStatsStrings() {
        let stats = DailyStats(done: 3, snoozed: 1, skipped: 1, longestBoutSeconds: 72 * 60)
        XCTAssertEqual(MenuBarState.statsLine(day: "Today", stats: stats), "Today · 1 snoozed · 1 skipped")
        XCTAssertEqual(MenuBarState.longestBoutLine(seconds: 72 * 60), "Longest sitting bout 1 h 12 m")
        XCTAssertEqual(MenuBarState.longestBoutLine(seconds: 35 * 60), "Longest sitting bout 35 m")
    }

    // MARK: - Shortcuts

    func testTheTwoShortcutsEveryMacAppIsExpectedToHave() {
        XCTAssertEqual(MenuShortcutSpec.settings.key, ",")
        XCTAssertEqual(MenuShortcutSpec.settings.label, "⌘,")
        XCTAssertEqual(MenuShortcutSpec.quit.key, "q")
        XCTAssertEqual(MenuShortcutSpec.quit.label, "⌘Q")
    }

    func testBothShortcutsAreBoundInTheSource() throws {
        let sources = [
            "Sources/movez/UI/MenuBar/MenuBarView.swift",
            "Sources/movez/App/movezApp.swift"
        ]
        for path in sources {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(path)
            let source = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(source.contains("keyboardShortcut(MenuShortcutSpec.settings.keyEquivalent"), path)
            XCTAssertTrue(source.contains("keyboardShortcut(MenuShortcutSpec.quit.keyEquivalent"), path)
        }
    }

    // MARK: - Pause options

    func testPauseOptionsCarryTheirOwnLengths() {
        XCTAssertEqual(PauseOption.allCases.map(\.label), ["15 m", "30 m", "1 h", "2 h", "Rest of day"])
        XCTAssertEqual(PauseOption.fifteenMinutes.seconds, 900)
        XCTAssertEqual(PauseOption.twoHours.seconds, 7_200)
        XCTAssertNil(PauseOption.restOfDay.seconds, "the rest of the day is not a fixed length")
        XCTAssertEqual(PauseOption.extendable.count, 3)
    }
}
