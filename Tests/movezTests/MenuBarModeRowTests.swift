import XCTest
@testable import movez

/// The dropdown's mode row and the Strength header and away copy (S1, S2, S12): the row lists the
/// modes from `ModeDefinition` wherever the menu lists rows, one click goes through `ModeSwitch`,
/// and a first switch to Strength closes the dropdown and asks for the setup instead.
@MainActor
final class MenuBarModeRowTests: XCTestCase {
    /// Saturday 12 September 2026 at 10:41 — outside the standard working week.
    private static let saturday: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 12
        components.hour = 10
        components.minute = 41
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 1_789_209_660)
    }()

    private var modeIds: [String] { ModeDefinition.all.map(\.id) }

    /// What the dropdown asked for: how many times it closed itself, and the actions it emitted.
    private final class Recorder {
        var closes = 0
        var actions: [ModeSwitchAction] = []
    }

    private func menu(_ harness: CoordinatorHarness, recorder: Recorder) -> MenuBarViewModel {
        MenuBarViewModel(coordinator: harness.coordinator) { recorder.actions.append($0) }
    }

    private func select(_ mode: BreakMode, in menu: MenuBarViewModel, recorder: Recorder) {
        menu.actions(closingWith: { recorder.closes += 1 }).selectMode(mode.rawValue)
    }

    private func strengthHarness(configure: (SettingsStore) -> Void = { _ in }) -> CoordinatorHarness {
        CoordinatorHarness(workingHours: .alwaysOn) { settings in
            settings.microEnabled = false
            settings.strengthSetUp = true
            settings.strengthBreaksPerDay = 3
            settings.mode = .strength
            configure(settings)
        }
    }

    // MARK: - The row

    func testTheModeRowListsTheModesFromTheDefinitionsInEveryStateThatListsRows() {
        XCTAssertEqual(modeIds, BreakMode.allCases.map(\.rawValue), "one segment per mode, in order")

        let sitting = CoordinatorHarness(workingHours: .alwaysOn)
        sitting.run(seconds: 10 * 60)
        let sittingMenu = menu(sitting, recorder: Recorder())
        XCTAssertEqual(sittingMenu.state.mode, .sitting)
        XCTAssertEqual(sittingMenu.state.modes.map(\.id), modeIds)
        XCTAssertEqual(sittingMenu.state.breakMode, .movement, "the segment in use is the mode in use")

        sittingMenu.pause(.thirtyMinutes)
        XCTAssertEqual(sittingMenu.state.mode, .paused)
        XCTAssertEqual(sittingMenu.state.modes.map(\.id), modeIds)

        let offHours = CoordinatorHarness(workingHours: .standard, startAt: Self.saturday)
        offHours.run(seconds: 10)
        let offHoursMenu = menu(offHours, recorder: Recorder())
        XCTAssertEqual(offHoursMenu.state.mode, .offHours)
        XCTAssertEqual(offHoursMenu.state.modes.map(\.id), modeIds)

        let away = CoordinatorHarness(workingHours: .alwaysOn)
        away.run(seconds: 50 * 60)
        away.coordinator.inject(.idle(seconds: 6 * 60))
        away.run(seconds: 20 * 60)
        let awayMenu = menu(away, recorder: Recorder())
        XCTAssertEqual(awayMenu.state.mode, .away)
        XCTAssertEqual(awayMenu.state.modes.map(\.id), modeIds)
    }

    /// Once Strength is set up, one click switches through `ModeSwitch`, both ways, and nothing
    /// else happens: the dropdown stays open and Settings is not asked for.
    func testAClickCallsTheSwitchEntryPoint() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn) { $0.strengthSetUp = true }
        let recorder = Recorder()
        let menu = menu(harness, recorder: recorder)

        select(.strength, in: menu, recorder: recorder)
        XCTAssertEqual(harness.settings.mode, .strength)
        XCTAssertEqual(menu.state.breakMode, .strength, "the row and the icon follow at once")

        select(.movement, in: menu, recorder: recorder)
        XCTAssertEqual(harness.settings.mode, .movement)
        XCTAssertEqual(menu.state.breakMode, .movement)

        XCTAssertEqual(recorder.closes, 0)
        XCTAssertEqual(recorder.actions, [])
    }

    func testClickingTheModeInUseDoesNothing() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        let recorder = Recorder()
        let menu = menu(harness, recorder: recorder)

        select(.movement, in: menu, recorder: recorder)
        XCTAssertEqual(harness.settings.mode, .movement)
        XCTAssertEqual(recorder.closes, 0)
        XCTAssertEqual(recorder.actions, [])
    }

    /// S2: the first switch to Strength closes the dropdown and asks for the setup, leaving the
    /// mode on Movement; after the setup is confirmed a switch is instant and asks for nothing.
    func testAFirstSwitchClosesTheDropdownAndAsksForTheSetupThenLaterSwitchesAreInstant() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        let recorder = Recorder()
        let menu = menu(harness, recorder: recorder)

        select(.strength, in: menu, recorder: recorder)
        XCTAssertEqual(recorder.closes, 1, "the dropdown closes")
        XCTAssertEqual(recorder.actions, [.openSetup(.strength)], "Settings is asked to open at the setup")
        XCTAssertEqual(harness.settings.mode, .movement, "the mode waits for the setup to be confirmed")
        XCTAssertEqual(menu.state.breakMode, .movement)

        ModeSwitch.confirmStrengthSetup(StrengthSetupChoices(), in: harness.settings)
        harness.coordinator.settingsChanged()
        select(.movement, in: menu, recorder: recorder)
        XCTAssertEqual(harness.settings.mode, .movement)

        select(.strength, in: menu, recorder: recorder)
        XCTAssertEqual(harness.settings.mode, .strength, "a later switch changes the mode")
        XCTAssertEqual(menu.state.breakMode, .strength)
        XCTAssertEqual(recorder.closes, 1, "and leaves the dropdown open")
        XCTAssertEqual(recorder.actions, [.openSetup(.strength)], "with no further settings action")
    }

    /// The default action opens the settings window and names the mode whose setup to show.
    func testTheDefaultSetupActionOpensSettingsNamingTheMode() {
        let expectation = expectation(forNotification: .movezOpenSettings, object: nil) { note in
            note.userInfo?[Notification.Name.modeSetupKey] as? String == BreakMode.strength.rawValue
        }
        MenuBarViewModel.openSetup(.openSetup(.strength))
        wait(for: [expectation], timeout: 1)
    }

    // MARK: - Header subtitle

    func testTheStrengthHeaderNamesWhereInTheDayTheNextBreakFalls() {
        let harness = strengthHarness()
        harness.run(seconds: 10 * 60)
        let menu = menu(harness, recorder: Recorder())

        XCTAssertEqual(menu.state.title, "Next break in 45 min")
        XCTAssertEqual(menu.state.subtitle, "Strength · A day · break 1 of 3")
    }

    func testTheSubtitleStrings() {
        let strength = ModeDayProgress(dayLetter: .dayB, breakNumber: 2, breaksPerDay: 3)
        XCTAssertEqual(strength.menuSubtitle, "Strength · B day · break 2 of 3")
        let endRange = ModeDayProgress(dayLetter: .dayA, breakNumber: nil, breaksPerDay: 3)
        XCTAssertEqual(endRange.menuSubtitle, "Strength · end-range break")
    }

    /// Movement keeps its header as it was: the title alone.
    func testTheMovementHeaderHasNoSubtitle() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        harness.run(seconds: 10 * 60)
        XCTAssertEqual(menu(harness, recorder: Recorder()).state.subtitle, "")
    }

    // MARK: - Away

    func testStrengthAwayUnderTheResetSettingSaysTheTimerRestarts() {
        let harness = strengthHarness { $0.awayBehaviour = .reset }
        harness.run(seconds: 50 * 60)
        harness.coordinator.inject(.idle(seconds: 6 * 60))
        harness.run(seconds: 20 * 60)
        let menu = menu(harness, recorder: Recorder())

        XCTAssertEqual(menu.state.mode, .away)
        XCTAssertEqual(menu.state.subtitle, "Timer restarts when you’re back. Strength break 1 of 3 is still next.")
    }

    /// The pause setting holds the countdown where it stood when the user went: 44 minutes into
    /// the 55-minute bout, so 11 left.
    func testStrengthAwayUnderThePauseSettingSaysWhatTheCountdownHolds() {
        let harness = strengthHarness { $0.awayBehaviour = .pause }
        harness.run(seconds: 50 * 60)
        harness.coordinator.inject(.idle(seconds: 6 * 60))
        harness.run(seconds: 20 * 60)
        let menu = menu(harness, recorder: Recorder())

        XCTAssertEqual(menu.state.mode, .away)
        XCTAssertEqual(
            menu.state.subtitle,
            "Countdown paused with 11 min left. Strength break 1 of 3 is still next."
        )
    }

    func testTheAwayStrings() {
        let strength = ModeDayProgress(dayLetter: .dayA, breakNumber: 2, breaksPerDay: 3)
        XCTAssertEqual(
            strength.awaySubtitle(behaviour: .reset, minutesLeft: 23),
            "Timer restarts when you’re back. Strength break 2 of 3 is still next."
        )
        XCTAssertEqual(
            strength.awaySubtitle(behaviour: .pause, minutesLeft: 23),
            "Countdown paused with 23 min left. Strength break 2 of 3 is still next."
        )
        let endRange = ModeDayProgress(dayLetter: .dayA, breakNumber: nil, breaksPerDay: 3)
        XCTAssertEqual(endRange.awaySubtitle(behaviour: .reset, minutesLeft: 23), "Timer restarts when you’re back.")
        XCTAssertEqual(endRange.awaySubtitle(behaviour: .pause, minutesLeft: 23), "Countdown paused with 23 min left.")
    }

    // MARK: - Make due

    func testTheMakeDueSummaryReadsTheOffers() {
        let joined = MenuBarState.makeDueMinutes.map(String.init).joined(separator: " · ") + " min"
        XCTAssertEqual(MenuBarState.makeDueSummary, joined)
    }
}
