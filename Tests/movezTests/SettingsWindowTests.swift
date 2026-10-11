import XCTest
@testable import movez

@MainActor
final class SettingsWindowTests: XCTestCase {
    private let library = RoutineTestSupport.library

    private func makeViewModel(
        launchAtLogin: FakeLaunchAtLogin? = nil,
        onChange: @escaping () -> Void = {}
    ) -> SettingsViewModel {
        let suite = UserDefaults(suiteName: "movez.tests.\(UUID().uuidString)") ?? .standard
        return SettingsViewModel(
            settings: SettingsStore(defaults: suite),
            library: library,
            launchAtLogin: launchAtLogin ?? FakeLaunchAtLogin(),
            onChange: onChange
        )
    }

    // MARK: - Preset and the custom stepper

    func testCustomShowsItsStepperAndTheStepperStaysOnTheLadder() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.settings.preset, .fiftyFiveFive)

        viewModel.setPreset(.custom)
        XCTAssertEqual(viewModel.settings.preset, .custom)
        XCTAssertEqual(viewModel.customSitLabel, "45 min")

        viewModel.stepCustomMinutes(by: 1)
        XCTAssertEqual(viewModel.settings.customSitMinutes, 50)
        viewModel.stepCustomMinutes(by: -3)
        XCTAssertEqual(viewModel.settings.customSitMinutes, 35)

        viewModel.setCustomMinutes(7)
        XCTAssertEqual(viewModel.settings.customSitMinutes, 15, "the ladder starts at 15")
        viewModel.setCustomMinutes(500)
        XCTAssertEqual(viewModel.settings.customSitMinutes, 120, "and stops at 120")
        viewModel.setCustomMinutes(63)
        XCTAssertEqual(viewModel.settings.customSitMinutes, 60, "in steps of five")
    }

    func testTheMicroToggleIsHiddenForBoutsTooShortToNeedIt() {
        let viewModel = makeViewModel()
        XCTAssertTrue(viewModel.settings.microToggleAvailable, "55/5")

        viewModel.setPreset(.twentyFiveFive)
        XCTAssertFalse(viewModel.settings.microToggleAvailable, "a 25-minute bout is already short")

        viewModel.setPreset(.custom)
        viewModel.setCustomMinutes(40)
        XCTAssertFalse(viewModel.settings.microToggleAvailable)
        viewModel.setCustomMinutes(45)
        XCTAssertTrue(viewModel.settings.microToggleAvailable)
    }

    // MARK: - Working hours

    func testWorkingHoursSummarisesAndRefusesABackwardsDay() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.workingHoursSummary, "Mon–Fri · 9:00–18:00")

        viewModel.beginEditingHours()
        XCTAssertEqual(viewModel.openSheet, .workingHours)

        // `days` is indexed by weekday − 1, so Sunday is 0 and Friday is 5.
        viewModel.hoursDraft.days[5].endMinutes = 13 * 60
        viewModel.applyHours()
        XCTAssertNil(viewModel.hoursError)
        XCTAssertNil(viewModel.openSheet)
        XCTAssertEqual(viewModel.workingHoursSummary, "Mon–Thu · 9:00–18:00, Fri · 9:00–13:00")
    }

    func testABackwardsDayShowsTheRuleAndChangesNothing() {
        let viewModel = makeViewModel()
        let before = viewModel.settings.workingHours

        viewModel.beginEditingHours()
        viewModel.hoursDraft.days[5].startMinutes = 18 * 60
        viewModel.hoursDraft.days[5].endMinutes = 9 * 60
        viewModel.applyHours()

        XCTAssertEqual(viewModel.hoursError, "End must be after start (Fri)")
        XCTAssertEqual(viewModel.openSheet, .workingHours, "the sheet stays open on a refusal")
        XCTAssertEqual(viewModel.settings.workingHours, before)
    }

    // MARK: - Movements

    func testEquipmentChipsAreTheFourTheIntakeSettled() {
        XCTAssertEqual(
            SettingsViewModel.equipmentOptions.map(\.displayName),
            ["Band", "Kettlebell or dumbbell", "Roller", "Ball"]
        )
        XCTAssertEqual(
            SettingsViewModel.equipmentOptions.map(\.rawValue),
            ["band", "kettlebell_or_dumbbell", "foam_roller", "ball"]
        )
    }

    func testTogglingAChipAddsAndRemovesIt() {
        let viewModel = makeViewModel()
        XCTAssertTrue(viewModel.settings.equipment.isEmpty)

        viewModel.toggleEquipment(.band)
        XCTAssertEqual(viewModel.settings.equipment, [.band])
        viewModel.toggleEquipment(.band)
        XCTAssertTrue(viewModel.settings.equipment.isEmpty)
    }

    func testDifficultySegmentsAreTheThreeCaps() {
        XCTAssertEqual(SettingsViewModel.difficultyOptions.map(\.value), [1, 2, 3])
        XCTAssertEqual(SettingsViewModel.difficultyOptions.map(\.label), ["Beginner", "Moderate", "Advanced"])
    }

    /// Every focus is a body region. "More balance" went when balance joined every break.
    func testFocusOptionsAreExactlyTheSix() {
        XCTAssertEqual(
            SettingsViewModel.focusOptions.map(\.label),
            ["None", "More upper back", "More hips", "More neck and shoulders", "More hands and eyes", "More core"]
        )
        XCTAssertEqual(
            SettingsViewModel.focusOptions.map(\.value),
            [.none, .moreUpperBack, .moreHips, .moreNeckShoulders, .moreHandsEyes, .moreCore]
        )
    }

    // MARK: - The library browser

    func testSearchFindsEveryHipAndNothingElse() {
        let viewModel = makeViewModel()
        viewModel.librarySearch = "HIP"
        let found = viewModel.matchingMovements()

        XCTAssertFalse(found.isEmpty)
        for movement in found {
            XCTAssertTrue(
                movement.name.lowercased().contains("hip") || movement.id.lowercased().contains("hip"),
                movement.name
            )
        }
        let expected = library.movements.filter {
            $0.name.lowercased().contains("hip") || $0.id.lowercased().contains("hip")
        }
        XCTAssertEqual(found.map(\.id), expected.map(\.id), "case-insensitive, and nothing missed")
    }

    func testTheBucketFilterNarrowsTheSearch() {
        let viewModel = makeViewModel()
        viewModel.librarySearch = "hip"
        viewModel.libraryBucket = .flx
        XCTAssertTrue(viewModel.matchingMovements().allSatisfy { $0.bucket == .flx })
    }

    func testExcludingAMovementCountsItAndKeepsItOutOfEveryRoutine() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.excludedLine, "0 excluded")

        viewModel.setExcluded("CIR-02", true)
        XCTAssertEqual(viewModel.excludedLine, "1 excluded")
        XCTAssertTrue(viewModel.settings.excludedMovementIds.contains("CIR-02"))

        var context = RoutineContext()
        context.excluded = viewModel.settings.excludedMovementIds
        let routine = RoutineTestSupport.builder.build(context: context)
        XCTAssertFalse(routine.movementIds.contains("CIR-02"))

        viewModel.setExcluded("CIR-02", false)
        XCTAssertEqual(viewModel.excludedLine, "0 excluded")
    }

    // MARK: - Staying out of the way

    func testAwayThresholdIsClampedToTheOfferedRange() {
        let viewModel = makeViewModel()
        XCTAssertEqual(SettingsViewModel.awayOptions.map(\.value), Array(2...10))
        XCTAssertEqual(SettingsViewModel.awayOptions.first?.label, "2 min")

        viewModel.setAwayMinutes(7)
        XCTAssertEqual(viewModel.settings.awayThresholdMinutes, 7)
        XCTAssertEqual(viewModel.settings.schedulerConfig.awayThresholdSeconds, 420)

        viewModel.setAwayMinutes(30)
        XCTAssertEqual(viewModel.settings.awayThresholdMinutes, 10)
        viewModel.setAwayMinutes(0)
        XCTAssertEqual(viewModel.settings.awayThresholdMinutes, 2)
    }

    func testExceptionsAreAddedOnceAndCountedInWords() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.exceptionsLine, "0 exceptions")

        viewModel.addException("com.apple.iWork.Keynote")
        XCTAssertEqual(viewModel.exceptionsLine, "1 exception")
        viewModel.addException("com.apple.iWork.Keynote")
        XCTAssertEqual(viewModel.settings.fullscreenExceptions.count, 1, "no duplicates")
        viewModel.addException("")
        XCTAssertEqual(viewModel.settings.fullscreenExceptions.count, 1, "and no empty entry")

        viewModel.addException("us.zoom.xos")
        XCTAssertEqual(viewModel.exceptionsLine, "2 exceptions")
        viewModel.removeException("us.zoom.xos")
        XCTAssertEqual(viewModel.settings.fullscreenExceptions, ["com.apple.iWork.Keynote"])
    }

    // MARK: - General

    func testSoundsOffMeansNothingIsPlayed() {
        let viewModel = makeViewModel()
        let recorder = RecordingChimePlayer()
        let player = GatedChimePlayer(wrapping: recorder, isEnabled: { [settings = viewModel.settings] in
            settings.soundsEnabled
        })

        player.play(.headsUp)
        XCTAssertEqual(recorder.played, [.headsUp])

        viewModel.setSounds(false)
        player.play(.completion)
        XCTAssertEqual(recorder.played, [.headsUp], "the toggle is read at play time")
    }

    func testLaunchAtLoginRegistersAndSurfacesARefusal() {
        let service = FakeLaunchAtLogin()
        let viewModel = makeViewModel(launchAtLogin: service)

        viewModel.setLaunchAtLogin(true)
        XCTAssertEqual(service.calls, [true])
        XCTAssertTrue(viewModel.settings.launchAtLogin)
        XCTAssertNil(viewModel.launchAtLoginError)

        service.failure = LaunchAtLoginError.unsigned
        viewModel.setLaunchAtLogin(false)
        XCTAssertEqual(viewModel.launchAtLoginError, "macOS refused the login item")
        XCTAssertTrue(viewModel.settings.launchAtLogin, "the toggle follows the system, not the tap")
    }

    func testTheFooterSaysWhatIsInstalled() {
        let viewModel = makeViewModel()
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        XCTAssertEqual(
            viewModel.versionLine,
            "movez \(version) (\(build)) · library v\(viewModel.library.version) · \(viewModel.library.movements.count) movements"
        )
    }

    func testTheFooterIsBuiltFromWhatItIsGiven() throws {
        let library = try LibraryLoader.loadBundled()
        let line = SettingsViewModel.versionLine(
            info: ["CFBundleShortVersionString": "0.7.2", "CFBundleVersion": "51"],
            library: library
        )
        XCTAssertEqual(line, "movez 0.7.2 (51) · library v\(library.version) · \(library.movements.count) movements")
    }

    /// The version is set once in `project.yml` and the build number is stamped from the commit
    /// count; neither should ever reach the app as an unexpanded build setting or a placeholder.
    func testTheAppVersionIsPreReleaseSemverAndTheBuildNumberIsStamped() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        XCTAssertNotNil(version.range(of: #"^0\.\d+\.\d+$"#, options: .regularExpression), version)
        let build = Int(info["CFBundleVersion"] as? String ?? "") ?? 0
        XCTAssertGreaterThan(build, 1, "the build number should be the commit count")
    }

    // MARK: - Every write reaches the scheduler

    func testEverySettingAsksTheSchedulerToRePlan() {
        var changes = 0
        let viewModel = makeViewModel(onChange: { changes += 1 })

        viewModel.setPreset(.eightyFiveFive)
        viewModel.setMicroEnabled(false)
        viewModel.toggleEquipment(.ball)
        viewModel.setDifficultyCap(3)
        viewModel.setFocus(.moreHips)
        viewModel.setExcluded("BRE-01", true)
        viewModel.setSuppressMic(false)
        viewModel.setSuppressCapture(false)
        viewModel.setSuppressFullscreen(false)
        viewModel.setAwayMinutes(5)
        viewModel.setSounds(false)

        XCTAssertEqual(changes, 11)
    }
}
