import Combine
import XCTest
@testable import movez

/// The Strength parts of the settings window: the STRENGTH section, the strength library browser
/// and the first-switch setup sheet.
@MainActor
final class StrengthSettingsWindowTests: XCTestCase {
    private static let strengthKeys: Set<String> = [
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
            strengthLibrary: RoutineTestSupport.strengthLibrary,
            launchAtLogin: FakeLaunchAtLogin(),
            onModeAction: onModeAction
        )
    }

    /// The keys whose stored value differs between two reads of the suite.
    private func changedKeys(_ before: [String: Any], _ after: [String: Any]) -> Set<String> {
        let keys = Set(before.keys).union(after.keys)
        return keys.filter { key in
            switch (before[key] as? NSObject, after[key] as? NSObject) {
            case let (lhs?, rhs?): return lhs != rhs
            case (nil, nil): return false
            default: return true
            }
        }
    }

    // MARK: - Changes made outside the window

    /// The menu bar's mode row writes straight to the shared store, so an open Settings window
    /// must hear about it to swap MOVEMENTS for STRENGTH and move the MODE control.
    func testAModeChangeMadeOnTheStoreRepublishesTheViewModel() {
        let viewModel = makeViewModel()
        var published = 0
        let subscription = viewModel.objectWillChange.sink { _ in published += 1 }
        defer { subscription.cancel() }

        viewModel.settings.mode = .strength

        XCTAssertGreaterThan(published, 0)
    }

    // MARK: - The STRENGTH section

    func testEveryStrengthSectionControlWritesOnlyStrengthKeys() {
        let suite = ScratchDefaults.make()
        let viewModel = makeViewModel(suite: suite)
        viewModel.settings.strengthSetUp = true
        viewModel.settings.mode = .strength
        let before = suite.dictionaryRepresentation()

        // The section's controls, in the order it draws them.
        viewModel.toggleStrengthEquipment(.dumbbells)
        viewModel.toggleStrengthEquipment(.kettlebell)
        viewModel.setStrengthSolidWallNearby(false)
        viewModel.setStrengthBreaksPerDay(4)
        viewModel.setStrengthDifficultyCap(3)
        viewModel.setStrengthFocus(.moreArms)
        let first = RoutineTestSupport.strengthLibrary.movements[0].id
        viewModel.setStrengthExcluded(first, true)

        let changed = changedKeys(before, suite.dictionaryRepresentation())
        XCTAssertFalse(changed.isEmpty)
        XCTAssertTrue(changed.isSubset(of: Self.strengthKeys), "wrote \(changed.subtracting(Self.strengthKeys))")
        XCTAssertEqual(viewModel.strengthExcludedLine, "1 excluded")
    }

    func testTheModeSectionShowsTheChosenModesGroup() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.settings.mode.definition.settingsGroup, .movements)
        viewModel.settings.strengthSetUp = true
        viewModel.requestMode(id: BreakMode.strength.rawValue)
        XCTAssertEqual(viewModel.settings.mode.definition.settingsGroup, .strength)
        viewModel.requestMode(id: "not a mode")
        XCTAssertEqual(viewModel.settings.mode, .strength)
    }

    // MARK: - The strength library browser

    func testTheBrowserListsTheWholeStrengthLibraryUnderItsOwnBuckets() {
        let viewModel = makeViewModel()
        viewModel.openStrengthLibrary()

        XCTAssertEqual(viewModel.openSheet, .modeLibrary)
        XCTAssertEqual(viewModel.matchingStrengthMovements().count, 145)
        XCTAssertEqual(viewModel.strengthShownLine, "145 shown")
        let chips = ["All"] + viewModel.strengthBucketChips.map(\.bucket.rawValue)
        XCTAssertEqual(chips, ["All", "SQT", "HNG", "PSH", "PUL", "COR", "ACC", "END"])
        // The design drew WRM and LEG; the library has no such buckets (SPEC reconciliation 10).
        XCTAssertFalse(chips.contains("WRM"))
        XCTAssertFalse(chips.contains("LEG"))
        XCTAssertEqual(
            viewModel.strengthBucketChips.map(\.name),
            RoutineTestSupport.strengthLibrary.buckets.map(\.name)
        )
    }

    func testTheBucketChipAndSearchNarrowTheList() {
        let viewModel = makeViewModel()
        let library = RoutineTestSupport.strengthLibrary
        viewModel.strengthLibraryBucket = .end
        XCTAssertEqual(viewModel.matchingStrengthMovements().count, library.movements(in: .end).count)
        XCTAssertTrue(viewModel.matchingStrengthMovements().allSatisfy { $0.bucket == .end })

        viewModel.strengthLibraryBucket = nil
        let target = library.movements[3]
        viewModel.librarySearch = target.id.lowercased()
        XCTAssertEqual(viewModel.matchingStrengthMovements().map(\.id), [target.id])
    }

    func testARowsToggleExcludesTheMoveAndItsMetaComesFromTheLibrary() throws {
        let viewModel = makeViewModel()
        let library = RoutineTestSupport.strengthLibrary
        let loaded = try XCTUnwrap(library.movements.first { $0.equipment.count == 2 })
        let bucketName = try XCTUnwrap(library.buckets.first { $0.id == loaded.bucket }?.name)

        XCTAssertTrue(viewModel.strengthMeta(for: loaded).hasPrefix("\(bucketName) · Diff \(loaded.difficulty) · "))
        XCTAssertTrue(viewModel.strengthMeta(for: loaded).contains("dumbbell or kettlebell"))
        let perSide = try XCTUnwrap(library.movements.first { $0.perSide })
        XCTAssertTrue(viewModel.strengthMeta(for: perSide).contains(" · /side"))
        let micro = try XCTUnwrap(library.movements.first { $0.microEligible })
        XCTAssertTrue(viewModel.strengthMeta(for: micro).hasSuffix(" · micro"))
        let bodyweight = try XCTUnwrap(library.movements.first { $0.isBodyweight && !$0.perSide && !$0.microEligible })
        let bodyweightName = viewModel.strengthBucketName(bodyweight.bucket)
        XCTAssertEqual(viewModel.strengthMeta(for: bodyweight), "\(bodyweightName) · Diff \(bodyweight.difficulty)")

        viewModel.setStrengthExcluded(loaded.id, true)
        XCTAssertTrue(viewModel.isStrengthExcluded(loaded.id))
        XCTAssertTrue(viewModel.settings.excludedMovementIds.isEmpty, "the movement exclusions are untouched")
        viewModel.setStrengthExcluded(loaded.id, false)
        XCTAssertFalse(viewModel.isStrengthExcluded(loaded.id))
    }

    // MARK: - The first-switch sheet

    func testTheFirstRequestOpensTheSheetAtTheAgreedDefaults() {
        var actions: [ModeSwitchAction] = []
        let viewModel = makeViewModel { actions.append($0) }
        viewModel.strengthSetupDraft.breaksPerDay = 1

        viewModel.requestMode(.strength)

        XCTAssertEqual(viewModel.openSheet, .modeSetup)
        XCTAssertEqual(actions, [.openSetup(.strength)])
        XCTAssertEqual(viewModel.settings.mode, .movement)
        XCTAssertEqual(viewModel.strengthSetupDraft.difficultyCap, 1, "Beginner")
        XCTAssertEqual(viewModel.strengthSetupDraft.breaksPerDay, 3)
        XCTAssertTrue(viewModel.strengthSetupDraft.equipment.isEmpty)
        XCTAssertTrue(viewModel.strengthSetupDraft.solidWallNearby)
    }

    func testSwitchToStrengthIsEnabledWithNothingTickedAndSavesTheChoices() {
        let suite = ScratchDefaults.make()
        let viewModel = makeViewModel(suite: suite)
        viewModel.requestMode(.strength)
        XCTAssertTrue(viewModel.strengthSetupCanConfirm, "allowed with nothing ticked")

        viewModel.strengthSetupDraft.solidWallNearby = false
        viewModel.strengthSetupDraft.breaksPerDay = 2
        viewModel.strengthSetupDraft.difficultyCap = 2
        viewModel.confirmStrengthSetupSheet()

        XCTAssertNil(viewModel.openSheet)
        let settings = SettingsStore(defaults: suite)
        XCTAssertEqual(settings.mode, .strength)
        XCTAssertTrue(settings.strengthSetUp)
        XCTAssertTrue(settings.strengthEquipment.isEmpty)
        XCTAssertFalse(settings.strengthSolidWallNearby)
        XCTAssertEqual(settings.strengthBreaksPerDay, 2)
        XCTAssertEqual(settings.strengthDifficultyCap, 2)
    }

    func testTickedEquipmentIsSavedOnlyOnConfirm() {
        let suite = ScratchDefaults.make()
        let viewModel = makeViewModel(suite: suite)
        viewModel.requestMode(.strength)
        viewModel.toggleSetupEquipment(.kettlebell)
        viewModel.toggleSetupEquipment(.dumbbells)
        viewModel.toggleSetupEquipment(.dumbbells)
        XCTAssertTrue(viewModel.settings.strengthEquipment.isEmpty, "a draft until Switch to Strength")

        viewModel.confirmStrengthSetupSheet()
        XCTAssertEqual(SettingsStore(defaults: suite).strengthEquipment, [.kettlebell])
    }

    func testNotNowClosesTheSheetAndChangesNothing() {
        let suite = ScratchDefaults.make()
        let viewModel = makeViewModel(suite: suite)
        viewModel.requestMode(.strength)
        viewModel.toggleSetupEquipment(.dumbbells)
        viewModel.strengthSetupDraft.breaksPerDay = 4
        let before = suite.dictionaryRepresentation()

        viewModel.declineStrengthSetup()

        XCTAssertNil(viewModel.openSheet)
        XCTAssertTrue(changedKeys(before, suite.dictionaryRepresentation()).isEmpty)
        XCTAssertEqual(viewModel.settings.mode, .movement)
        XCTAssertFalse(viewModel.settings.strengthSetUp)
    }

    func testTheSheetCarriesNoAtLeastOneGate() {
        // The design's "Choose at least one." note goes with the disabled button the spec
        // overruled (SPEC reconciliation 12), so the sheet has neither.
        let copy = [StrengthSetupSheet.intro, StrengthSettingsSection.breaksSub]
        XCTAssertFalse(copy.contains("Choose at least one."))
        XCTAssertTrue(makeViewModel().strengthSetupCanConfirm)
    }

    func testASetupRequestFromTheDropdownOpensTheSheet() {
        let viewModel = makeViewModel()
        viewModel.show(.openSetup(.strength))
        XCTAssertEqual(viewModel.openSheet, .modeSetup)
        viewModel.declineStrengthSetup()
        viewModel.show(.openSetup(.movement))
        XCTAssertNil(viewModel.openSheet, "only Strength has a setup sheet")
    }
}
