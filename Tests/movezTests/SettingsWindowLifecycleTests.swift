import XCTest
@testable import movez

/// What the settings window leaves behind when it closes, and what keeps running while it is shut.
@MainActor
final class SettingsWindowLifecycleTests: XCTestCase {
    private func makeViewModel(settings: SettingsStore? = nil) -> SettingsViewModel {
        SettingsViewModel(
            settings: settings ?? SettingsStore(defaults: ScratchDefaults.make()),
            library: RoutineTestSupport.library,
            strengthLibrary: RoutineTestSupport.strengthLibrary,
            launchAtLogin: FakeLaunchAtLogin()
        )
    }

    /// Lets the main run loop deliver what was published.
    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    // MARK: - UI-25

    /// Closing with the red button is "Not now": the next open is not the setup again.
    func testClosingTheWindowDeclinesAnOpenStrengthSetup() {
        let viewModel = makeViewModel()
        viewModel.requestMode(.strength)
        XCTAssertEqual(viewModel.openSheet, .modeSetup)

        viewModel.windowClosed()
        XCTAssertNil(viewModel.openSheet)
        XCTAssertNotEqual(viewModel.settings.mode, .strength, "nothing was confirmed")
    }

    func testClosingTheWindowDropsAHalfEditedWorkingHoursDraft() {
        let viewModel = makeViewModel()
        let saved = viewModel.settings.workingHours
        viewModel.beginEditingHours()
        viewModel.hoursDraft.days[5].startMinutes = 18 * 60
        viewModel.hoursDraft.days[5].endMinutes = 9 * 60
        viewModel.applyHours()
        XCTAssertNotNil(viewModel.hoursError)

        viewModel.windowClosed()
        XCTAssertNil(viewModel.openSheet)
        XCTAssertNil(viewModel.hoursError)
        XCTAssertEqual(viewModel.hoursDraft, saved)
        XCTAssertEqual(viewModel.settings.workingHours, saved)
    }

    // MARK: - UI-24

    /// The inspector follows the coordinator only while someone can see it: the window open and
    /// the Debug section expanded. Otherwise it republished the whole settings view model every
    /// poll until quit.
    func testTheInspectorRunsOnlyWhileTheWindowIsOpenAndTheSectionExpanded() {
        let harness = CoordinatorHarness(workingHours: .alwaysOn)
        let viewModel = makeViewModel(settings: harness.settings)
        let debug = DebugViewModel(coordinator: harness.coordinator)
        viewModel.attach(debug: debug)
        XCTAssertFalse(debug.isActive, "attached to a window nobody has opened")

        viewModel.windowOpened()
        XCTAssertFalse(debug.isActive, "the section is collapsed")

        viewModel.setDebugExpanded(true)
        XCTAssertTrue(debug.isActive)
        harness.run(seconds: 10)
        settle()
        XCTAssertEqual(viewModel.debug, debug.state, "the open section shows the live inspector")

        viewModel.windowClosed()
        XCTAssertFalse(debug.isActive)
        var publishes = 0
        let subscription = viewModel.objectWillChange.sink { publishes += 1 }
        harness.run(seconds: 60)
        settle()
        subscription.cancel()
        XCTAssertEqual(publishes, 0, "a closed window is not republished on every tick")

        viewModel.windowOpened()
        XCTAssertTrue(debug.isActive, "reopening with the section expanded resumes it")
        XCTAssertEqual(viewModel.debug, debug.state, "and shows the inspector as it is now")
    }
}
