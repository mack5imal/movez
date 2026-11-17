import XCTest
@testable import movez

@MainActor
final class ModeSettingsTests: XCTestCase {
    /// Every key a movement-mode setting is stored under. The mode itself is shared by both modes,
    /// so it is in neither list.
    private static let movementKeys: [String] = [
        SettingsStore.Key.preset, SettingsStore.Key.customSitMinutes, SettingsStore.Key.microEnabled,
        SettingsStore.Key.workingHours, SettingsStore.Key.equipment, SettingsStore.Key.difficultyCap,
        SettingsStore.Key.excludedMovementIds, SettingsStore.Key.focus, SettingsStore.Key.wallAvailable,
        SettingsStore.Key.floorAvailable, SettingsStore.Key.stairsAvailable
    ]

    private static let strengthKeys: [String] = [
        SettingsStore.Key.strengthSetUp, SettingsStore.Key.strengthEquipment,
        SettingsStore.Key.strengthSolidWallNearby, SettingsStore.Key.strengthBreaksPerDay,
        SettingsStore.Key.strengthDifficultyCap, SettingsStore.Key.strengthFocus,
        SettingsStore.Key.strengthExcludedIds
    ]

    private func makeViewModel(
        suite: UserDefaults = ScratchDefaults.make(),
        onModeAction: @escaping (ModeSwitchAction) -> Void = { _ in }
    ) -> SettingsViewModel {
        SettingsViewModel(
            settings: SettingsStore(defaults: suite),
            library: RoutineTestSupport.library,
            launchAtLogin: FakeLaunchAtLogin(),
            onModeAction: onModeAction
        )
    }

    // MARK: - The mode

    func testAFreshInstallIsInMovementModeAndStrengthPersists() {
        let suite = ScratchDefaults.make()
        let settings = SettingsStore(defaults: suite)
        XCTAssertEqual(settings.mode, .movement)
        XCTAssertNil(suite.object(forKey: SettingsStore.Key.mode), "nothing is stored until the mode changes")
        XCTAssertFalse(settings.strengthSetUp)

        settings.mode = .strength
        XCTAssertEqual(SettingsStore(defaults: suite).mode, .strength)
    }

    func testAnUnknownStoredModeReadsAsMovement() {
        let suite = ScratchDefaults.make()
        suite.set("hundreds", forKey: SettingsStore.Key.mode)
        XCTAssertEqual(SettingsStore(defaults: suite).mode, .movement)
    }

    func testStrengthDefaultsAndRelaunch() {
        let suite = ScratchDefaults.make()
        let settings = SettingsStore(defaults: suite)
        XCTAssertTrue(settings.strengthEquipment.isEmpty)
        XCTAssertTrue(settings.strengthSolidWallNearby)
        XCTAssertEqual(settings.strengthBreaksPerDay, 3)
        XCTAssertEqual(settings.strengthDifficultyCap, 1)
        XCTAssertEqual(settings.strengthFocus, .none)
        XCTAssertTrue(settings.strengthExcludedIds.isEmpty)

        settings.strengthSetUp = true
        settings.strengthEquipment = [.dumbbells, .kettlebell]
        settings.strengthSolidWallNearby = false
        settings.strengthBreaksPerDay = 2
        settings.strengthDifficultyCap = 3
        settings.strengthFocus = .moreArms
        settings.strengthExcludedIds = ["SQT-01"]

        let relaunched = SettingsStore(defaults: suite)
        XCTAssertTrue(relaunched.strengthSetUp)
        XCTAssertEqual(relaunched.strengthEquipment, [.dumbbells, .kettlebell])
        XCTAssertFalse(relaunched.strengthSolidWallNearby)
        XCTAssertEqual(relaunched.strengthBreaksPerDay, 2)
        XCTAssertEqual(relaunched.strengthDifficultyCap, 3)
        XCTAssertEqual(relaunched.strengthFocus, .moreArms)
        XCTAssertEqual(relaunched.strengthExcludedIds, ["SQT-01"])
    }

    func testAStoredBreaksCountOutsideTheRangeIsClamped() {
        let suite = ScratchDefaults.make()
        suite.set(9, forKey: SettingsStore.Key.strengthBreaksPerDay)
        XCTAssertEqual(SettingsStore(defaults: suite).strengthBreaksPerDay, 4)
    }

    // MARK: - The two modes' settings are separate

    func testChangingEveryStrengthSettingLeavesMovementSettingsAlone() {
        let suite = ScratchDefaults.make()
        let viewModel = makeViewModel(suite: suite)
        let settings = viewModel.settings
        setMovementSettingsAwayFromDefaults(settings)
        let movementBefore = movementValues(settings)
        let movementKeysBefore = stored(Self.movementKeys, in: suite)

        viewModel.toggleStrengthEquipment(.dumbbells)
        viewModel.toggleStrengthEquipment(.kettlebell)
        viewModel.setStrengthSolidWallNearby(false)
        viewModel.setStrengthBreaksPerDay(1)
        viewModel.setStrengthDifficultyCap(2)
        viewModel.setStrengthFocus(.moreBackAndShoulders)
        viewModel.setStrengthExcluded("PSH-01", true)
        viewModel.confirmStrengthSetup(StrengthSetupChoices(equipment: [.kettlebell]))

        XCTAssertEqual(movementValues(settings), movementBefore)
        XCTAssertEqual(movementValues(SettingsStore(defaults: suite)), movementBefore)
        XCTAssertEqual(stored(Self.movementKeys, in: suite), movementKeysBefore)
    }

    func testChangingEveryMovementSettingLeavesStrengthSettingsAlone() {
        let suite = ScratchDefaults.make()
        let viewModel = makeViewModel(suite: suite)
        let settings = viewModel.settings
        viewModel.confirmStrengthSetup(StrengthSetupChoices(
            equipment: [.dumbbells], solidWallNearby: false, breaksPerDay: 4, difficultyCap: 2
        ))
        viewModel.setStrengthFocus(.moreCore)
        viewModel.setStrengthExcluded("HNG-02", true)
        let strengthBefore = strengthValues(settings)
        let strengthKeysBefore = stored(Self.strengthKeys, in: suite)

        viewModel.toggleEquipment(.band)
        viewModel.toggleEquipment(.ball)
        viewModel.setWallAvailable(false)
        viewModel.setFloorAvailable(false)
        viewModel.setStairsAvailable(false)
        viewModel.setDifficultyCap(3)
        viewModel.setFocus(.moreHips)
        viewModel.setExcluded("FLX-01", true)
        viewModel.setPreset(.custom)
        viewModel.setCustomMinutes(75)
        viewModel.setMicroEnabled(false)
        var hours = WorkingHours.standard
        hours.days[6] = DayHours(enabled: true, startMinutes: 10 * 60, endMinutes: 14 * 60)
        settings.workingHours = hours

        XCTAssertEqual(strengthValues(settings), strengthBefore)
        XCTAssertEqual(strengthValues(SettingsStore(defaults: suite)), strengthBefore)
        XCTAssertEqual(stored(Self.strengthKeys, in: suite), strengthKeysBefore)
    }

    // MARK: - The option tables

    func testStrengthOptionsAreTheAgreedOnes() {
        XCTAssertEqual(
            SettingsViewModel.strengthFocusOptions.map(\.label),
            ["None", "More legs and glutes", "More back and shoulders", "More core", "More arms"]
        )
        XCTAssertEqual(SettingsViewModel.strengthBreaksOptions.map(\.value), [1, 2, 3, 4])
        XCTAssertEqual(SettingsStore.strengthBreaksDefault, 3)
        XCTAssertEqual(SettingsStore(defaults: ScratchDefaults.make()).strengthBreaksPerDay, 3)
        XCTAssertEqual(SettingsStore(defaults: ScratchDefaults.make()).strengthDifficultyCap, 1)
        XCTAssertEqual(StrengthSetupChoices().difficultyCap, 1)
        XCTAssertEqual(StrengthSetupChoices().breaksPerDay, 3)
        XCTAssertEqual(SettingsViewModel.strengthEquipmentOptions.map(\.displayName), ["Dumbbells", "Kettlebell"])
        XCTAssertEqual(SettingsViewModel.modeOptions.map(\.displayName), ["Movement", "Strength"])
    }

    // MARK: - The first switch

    func testTheFirstStrengthRequestOpensTheSetupAndKeepsMovement() {
        var actions: [ModeSwitchAction] = []
        let viewModel = makeViewModel { actions.append($0) }

        viewModel.requestMode(.strength)

        XCTAssertEqual(viewModel.settings.mode, .movement)
        XCTAssertFalse(viewModel.settings.strengthSetUp)
        XCTAssertEqual(actions, [.openSetup(.strength)])
    }

    func testConfirmingTheSetupWithNoEquipmentSwitchesToStrength() {
        var actions: [ModeSwitchAction] = []
        let suite = ScratchDefaults.make()
        let viewModel = makeViewModel(suite: suite) { actions.append($0) }
        viewModel.requestMode(.strength)

        viewModel.confirmStrengthSetup(StrengthSetupChoices(equipment: [], solidWallNearby: false, breaksPerDay: 2))

        let settings = SettingsStore(defaults: suite)
        XCTAssertEqual(settings.mode, .strength)
        XCTAssertTrue(settings.strengthSetUp)
        XCTAssertTrue(settings.strengthEquipment.isEmpty)
        XCTAssertFalse(settings.strengthSolidWallNearby)
        XCTAssertEqual(settings.strengthBreaksPerDay, 2)
        XCTAssertEqual(settings.strengthDifficultyCap, 1)
        XCTAssertEqual(actions.count, 1)
    }

    func testNotNowLeavesTheModeAndFlagUnchanged() {
        let suite = ScratchDefaults.make()
        let viewModel = makeViewModel(suite: suite)
        let keysBefore = stored(Self.strengthKeys + [SettingsStore.Key.mode], in: suite)

        viewModel.requestMode(.strength)
        viewModel.declineStrengthSetup()

        XCTAssertEqual(viewModel.settings.mode, .movement)
        XCTAssertFalse(viewModel.settings.strengthSetUp)
        XCTAssertEqual(stored(Self.strengthKeys + [SettingsStore.Key.mode], in: suite), keysBefore)
    }

    func testOnceSetUpARequestSwitchesStraightAway() {
        var actions: [ModeSwitchAction] = []
        var changes = 0
        let suite = ScratchDefaults.make()
        SettingsStore(defaults: suite).strengthSetUp = true
        let viewModel = SettingsViewModel(
            settings: SettingsStore(defaults: suite),
            library: RoutineTestSupport.library,
            launchAtLogin: FakeLaunchAtLogin(),
            onModeAction: { actions.append($0) },
            onChange: { changes += 1 }
        )

        viewModel.requestMode(.strength)
        XCTAssertEqual(viewModel.settings.mode, .strength)
        viewModel.requestMode(.movement)
        XCTAssertEqual(viewModel.settings.mode, .movement)
        viewModel.requestMode(.strength)

        XCTAssertEqual(viewModel.settings.mode, .strength)
        XCTAssertEqual(SettingsStore(defaults: suite).mode, .strength)
        XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(changes, 3, "every switch reaches the coordinator")
    }

    func testSwitchingBackToMovementNeverNeedsASetup() {
        let suite = ScratchDefaults.make()
        let settings = SettingsStore(defaults: suite)
        settings.mode = .strength
        XCTAssertNil(ModeSwitch.request(.movement, in: settings))
        XCTAssertEqual(settings.mode, .movement)
    }

    // MARK: - Helpers

    private func setMovementSettingsAwayFromDefaults(_ settings: SettingsStore) {
        settings.preset = .eightyFiveFive
        settings.customSitMinutes = 70
        settings.microEnabled = false
        var hours = WorkingHours.standard
        hours.days[5] = DayHours(enabled: true, startMinutes: 9 * 60, endMinutes: 12 * 60)
        settings.workingHours = hours
        settings.equipment = [.band, .foamRoller]
        settings.difficultyCap = 3
        settings.excludedMovementIds = ["FLX-01", "STR-09"]
        settings.focus = .moreCore
        settings.wallAvailable = false
        settings.floorAvailable = false
        settings.stairsAvailable = false
    }

    private struct MovementValues: Equatable {
        let preset: PresetId
        let customSitMinutes: Int
        let microEnabled: Bool
        let workingHours: WorkingHours
        let equipment: Set<Equipment>
        let difficultyCap: Int
        let excluded: Set<String>
        let focus: Focus
        let wall: Bool
        let floor: Bool
        let stairs: Bool
    }

    private func movementValues(_ settings: SettingsStore) -> MovementValues {
        MovementValues(
            preset: settings.preset, customSitMinutes: settings.customSitMinutes,
            microEnabled: settings.microEnabled, workingHours: settings.workingHours,
            equipment: settings.equipment, difficultyCap: settings.difficultyCap,
            excluded: settings.excludedMovementIds, focus: settings.focus,
            wall: settings.wallAvailable, floor: settings.floorAvailable, stairs: settings.stairsAvailable
        )
    }

    private struct StrengthValues: Equatable {
        let setUp: Bool
        let equipment: Set<StrengthEquipment>
        let wall: Bool
        let breaks: Int
        let cap: Int
        let focus: StrengthFocus
        let excluded: Set<String>
    }

    private func strengthValues(_ settings: SettingsStore) -> StrengthValues {
        StrengthValues(
            setUp: settings.strengthSetUp, equipment: settings.strengthEquipment,
            wall: settings.strengthSolidWallNearby, breaks: settings.strengthBreaksPerDay,
            cap: settings.strengthDifficultyCap, focus: settings.strengthFocus,
            excluded: settings.strengthExcludedIds
        )
    }

    /// The raw stored values, as property-list objects, so a key that is written with a different
    /// value, added or removed shows up as a change even when the property reads the same.
    private func stored(_ keys: [String], in suite: UserDefaults) -> [String: NSObject] {
        var values: [String: NSObject] = [:]
        for key in keys {
            if let value = suite.object(forKey: key) as? NSObject { values[key] = value }
        }
        return values
    }
}
