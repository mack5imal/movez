import XCTest
@testable import movez

@MainActor
final class SettingsStoreTests: XCTestCase {
    private func makeStore() -> (SettingsStore, UserDefaults) {
        let suite = UserDefaults(suiteName: "movez.tests.\(UUID().uuidString)") ?? .standard
        return (SettingsStore(defaults: suite), suite)
    }

    func testDefaults() {
        let (settings, _) = makeStore()
        XCTAssertEqual(settings.preset, .fiftyFiveFive)
        XCTAssertEqual(settings.customSitMinutes, 45)
        XCTAssertTrue(settings.microEnabled)
        XCTAssertEqual(settings.workingHours, .standard)
        XCTAssertTrue(settings.equipment.isEmpty)
        XCTAssertEqual(settings.difficultyCap, 2)
        XCTAssertTrue(settings.excludedMovementIds.isEmpty)
        XCTAssertEqual(settings.focus, .none)
        XCTAssertTrue(settings.wallAvailable)
        XCTAssertTrue(settings.floorAvailable)
        XCTAssertTrue(settings.stairsAvailable)
        XCTAssertEqual(settings.unavailableRequirements, [])
        XCTAssertTrue(settings.suppressMic)
        XCTAssertTrue(settings.suppressCapture)
        XCTAssertTrue(settings.suppressFullscreen)
        XCTAssertTrue(settings.fullscreenExceptions.isEmpty)
        XCTAssertEqual(settings.awayThresholdMinutes, 3)
        XCTAssertTrue(settings.soundsEnabled)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(settings.debugTimeScale, 1)
        XCTAssertFalse(settings.debugExpanded)
    }

    func testEverySettingSurvivesARelaunch() {
        let (settings, suite) = makeStore()
        settings.preset = .eightyFiveFive
        settings.customSitMinutes = 75
        settings.microEnabled = false
        settings.equipment = [.band, .ball]
        settings.difficultyCap = 3
        settings.excludedMovementIds = ["FLX-01", "STR-09"]
        settings.focus = .moreHandsEyes
        settings.wallAvailable = false
        settings.floorAvailable = false
        settings.stairsAvailable = false
        settings.suppressMic = false
        settings.fullscreenExceptions = ["us.zoom.xos"]
        settings.awayThresholdMinutes = 6
        settings.soundsEnabled = false
        settings.launchAtLogin = true
        settings.debugTimeScale = 60
        settings.debugExpanded = true
        var hours = WorkingHours.standard
        hours.days[6] = DayHours(enabled: true, startMinutes: 10 * 60, endMinutes: 14 * 60)
        settings.workingHours = hours

        let reloaded = SettingsStore(defaults: suite)
        XCTAssertEqual(reloaded.preset, .eightyFiveFive)
        XCTAssertEqual(reloaded.customSitMinutes, 75)
        XCTAssertFalse(reloaded.microEnabled)
        XCTAssertEqual(reloaded.equipment, [.band, .ball])
        XCTAssertEqual(reloaded.difficultyCap, 3)
        XCTAssertEqual(reloaded.excludedMovementIds, ["FLX-01", "STR-09"])
        XCTAssertEqual(reloaded.focus, .moreHandsEyes)
        XCTAssertEqual(reloaded.unavailableRequirements, [.wall, .floor, .stairs])
        XCTAssertFalse(reloaded.suppressMic)
        XCTAssertEqual(reloaded.fullscreenExceptions, ["us.zoom.xos"])
        XCTAssertEqual(reloaded.awayThresholdMinutes, 6)
        XCTAssertFalse(reloaded.soundsEnabled)
        XCTAssertTrue(reloaded.launchAtLogin)
        XCTAssertEqual(reloaded.debugTimeScale, 60)
        XCTAssertTrue(reloaded.debugExpanded)
        XCTAssertEqual(reloaded.workingHours, hours)
    }

    /// "More balance" was removed as a focus. A user who had chosen it gets no focus rather than a
    /// crash or a stuck picker.
    func testARemovedFocusReadsAsNone() {
        let (_, suite) = makeStore()
        suite.set("moreBalance", forKey: "focus")
        XCTAssertEqual(SettingsStore(defaults: suite).focus, .none)
    }

    func testSchedulerConfigDerivation() {
        let (settings, _) = makeStore()
        XCTAssertEqual(settings.schedulerConfig.sitSeconds, 55 * 60)
        XCTAssertTrue(settings.schedulerConfig.microEnabled)

        settings.preset = .twentyFiveFive
        XCTAssertEqual(settings.schedulerConfig.sitSeconds, 25 * 60)
        XCTAssertFalse(settings.schedulerConfig.microEnabled, "25/5 never serves micro-breaks")

        settings.preset = .custom
        settings.customSitMinutes = 35
        XCTAssertEqual(settings.schedulerConfig.sitSeconds, 35 * 60)
        XCTAssertFalse(settings.schedulerConfig.microEnabled, "a 35-minute bout is too short for a micro-break")

        settings.customSitMinutes = 90
        XCTAssertTrue(settings.schedulerConfig.microEnabled)

        settings.awayThresholdMinutes = 7
        XCTAssertEqual(settings.schedulerConfig.awayThresholdSeconds, 7 * 60)
        XCTAssertEqual(settings.schedulerConfig.workingHours, settings.workingHours)
    }

    func testMicroToggleAvailability() {
        let (settings, _) = makeStore()
        XCTAssertTrue(settings.microToggleAvailable)

        settings.preset = .twentyFiveFive
        XCTAssertFalse(settings.microToggleAvailable)

        settings.preset = .custom
        settings.customSitMinutes = 40
        XCTAssertFalse(settings.microToggleAvailable)
        settings.customSitMinutes = 45
        XCTAssertTrue(settings.microToggleAvailable)
    }

    func testAwayThresholdRange() {
        XCTAssertEqual(SettingsStore.awayThresholdRange, 2...10)
    }
}
