import Foundation

/// The frozen data every snapshot renders from — the "Hip reset" break the design handoff shows,
/// so a snapshot can be held next to `screenshots/2a-full-break-overlay.png` and compared.
enum SnapshotFixtures {
    static let routineName = "Hip reset"
    static let routineFocus = "hips and glutes"
    static let eyebrow = "HIP RESET · HIPS AND GLUTES"
    static let completionTitle = "Hips reset"

    static let movementName = "March in place"
    static let movementInstruction = """
        Lift each knee to hip height, swinging the opposite arm. Land softly through the whole \
        foot. Keep a pace you could hold a conversation at.
        """
    static let sideMovementName = "Standing hip flexor stretch"
    static let sideInstruction = """
        Right foot forward into a half-lunge, back knee soft. Tuck the tailbone and squeeze the \
        back glute until the front of the left hip opens.
        """
    static let collapsedMovementName = "Wall sit"

    static let stripNames = ["March in place", "Hip flexor /side", "Wall sit", "Box breathing"]

    static func strip(currentIndex: Int, sideIndex: Int? = nil) -> [StripItem] {
        stripNames.enumerated().map { index, name in
            let state: StripItem.State = index < currentIndex ? .done : (index == currentIndex ? .current : .upcoming)
            return StripItem(
                number: index + 1,
                name: name,
                state: state,
                sideIndex: state == .current ? sideIndex : nil
            )
        }
    }

    static let breakRemaining = "4:12 LEFT"
    static let blockNumerals = "0:42"
    static let nextBreakAt = "12:05"
    static let endSummary = "Four movements done. Next break at 12:05."
    static let streak = 4
    static let skipsToday = 1
}

/// The overlay states the snapshots render, built by hand so the PNGs can be held next to
/// `screenshots/2a-full-break-overlay.png` and compared line for line.
extension SnapshotFixtures {
    static func overlayRunning() -> OverlayState {
        var state = OverlayState()
        state.eyebrow = eyebrow
        state.headerTrailing = breakRemaining
        state.discNumerals = blockNumerals
        state.discLabel = "NEXT →"
        state.discProgress = 0.3
        state.movementName = movementName
        state.instruction = movementInstruction
        state.strip = strip(currentIndex: 0)
        state.snoozeAvailable = true
        state.skipEnabled = true
        state.skipsToday = skipsToday
        state.streak = streak
        return state
    }

    static func overlayCollapsed() -> OverlayState {
        var state = overlayRunning()
        state.headerTrailing = "1:52 LEFT"
        state.discNumerals = "0:27"
        state.discProgress = 0.55
        state.movementName = collapsedMovementName
        state.instruction = "Back flat against the wall, knees at ninety degrees, weight through the heels."
        state.instructionCollapsed = true
        state.strip = strip(currentIndex: 2)
        state.snoozeAvailable = false
        state.doneAvailable = true
        return state
    }

    static func overlaySide() -> OverlayState {
        var state = overlayRunning()
        state.headerTrailing = "3:20 LEFT"
        state.discNumerals = "0:19"
        state.discLabel = "THEN RIGHT"
        state.discProgress = 0.62
        state.discMode = .halfShare(sideIndex: 0)
        state.movementName = sideMovementName
        state.instruction = sideInstruction
        state.isSideBlock = true
        state.side = .left
        state.strip = strip(currentIndex: 1, sideIndex: 0)
        return state
    }

    static func overlayEnd() -> OverlayState {
        var state = OverlayState()
        state.phase = .complete
        state.eyebrow = "HIP RESET · COMPLETE"
        state.headerTrailing = "NEXT BREAK \(nextBreakAt)"
        state.completionTitle = completionTitle
        state.endSummary = endSummary
        state.streak = streak
        state.strip = strip(currentIndex: 4)
        return state
    }

    /// Among the longest names in the library, under one of its longest instructions — the
    /// combination that used to cut the name off with an ellipsis instead of shrinking it.
    static let longStripNames = [
        "Reverse lunge with overhead reach",
        "Half-kneeling hip flexor stretch",
        "Single-leg stand with arm reaches",
        "Towel or cushion single-leg stand"
    ]

    static func overlayLongName() -> OverlayState {
        var state = overlayRunning()
        state.movementName = longStripNames[0]
        state.instruction = """
            Step one foot back into a lunge, lowering the rear knee toward the floor while the front \
            knee stays over the ankle. At the bottom, reach both arms straight overhead and squeeze \
            the rear glute. Drive through the front heel to return. Alternate sides.
            """
        state.strip = longStripNames.enumerated().map { index, name in
            StripItem(number: index + 1, name: name, state: index == 0 ? .current : .upcoming)
        }
        return state
    }
}

/// The panel states the snapshots render.
///
/// Copy note: the design handoff's micro-break panels say "Shoulder rolls", which is placeholder
/// copy — there is no such movement in `movement-library-v4.json`. The fixture uses the real
/// shoulder micro-break the builder would actually serve, CIR-06 "Arm circles", which produces
/// the same eyebrow the handoff draws: "MICRO-BREAK · SHOULDERS".
@MainActor
extension SnapshotFixtures {
    /// A fixed instant, so every panel PNG is byte-identical between runs.
    static let panelInstant = Date(timeIntervalSince1970: 1_767_225_600)

    static let deferredSittingSeconds: TimeInterval = 5_700
    static let microCountInRemaining: TimeInterval = 21
    static let microRunningRemaining: TimeInterval = 44
    /// Sixty percent of the toast's time left, which is where the handoff draws its hairline.
    static let toastRemaining: TimeInterval = 9

    static func headsUp(deferred: Bool = false) -> PanelViewModel {
        let clock = ManualClock(now: panelInstant)
        let model = PanelViewModel(phase: .headsUp, clock: clock, startedAt: clock.now, totalSeconds: 60)
        model.routineName = routineName
        model.focus = routineFocus
        model.blockCount = 4
        model.breakMinutes = 5
        model.skipsToday = skipsToday
        // The deferred variant has spent its one snooze, so the button is gone rather than dead.
        model.snoozesLeft = deferred ? 0 : 2
        if deferred {
            model.deferred = PanelViewModel.DeferredInfo(sittingFor: deferredSittingSeconds, reason: .microphone)
        }
        return model
    }

    static func microCountIn() -> PanelViewModel {
        let clock = ManualClock(now: panelInstant)
        let model = PanelViewModel(
            phase: .microCountIn,
            clock: clock,
            startedAt: clock.now.addingTimeInterval(microCountInRemaining - 30),
            totalSeconds: 30
        )
        model.micro = microBreak()
        model.microSeconds = 60
        return model
    }

    static func microRunning() -> PanelViewModel {
        let clock = ManualClock(now: panelInstant)
        let model = PanelViewModel(
            phase: .microRunning,
            clock: clock,
            startedAt: clock.now.addingTimeInterval(microRunningRemaining - 60),
            totalSeconds: 60
        )
        model.micro = microBreak()
        model.microSeconds = 60
        return model
    }

    static func awayToast() -> PanelViewModel {
        let clock = ManualClock(now: panelInstant)
        let model = PanelViewModel(
            phase: .toast,
            clock: clock,
            startedAt: clock.now.addingTimeInterval(toastRemaining - TimeInterval(ToastInfo.defaultSecondsOnScreen)),
            totalSeconds: ToastInfo.defaultSecondsOnScreen
        )
        model.toast = ToastInfo(
            kind: .creditedFullBreak,
            awaySeconds: 7 * 60,
            nextBreakAt: toastNextBreak,
            reversal: .wasSittingAfterFullCredit
        )
        return model
    }

    /// 14:02 on the fixture's day — the time the handoff's toast shows.
    static let toastNextBreak = menuDate(month: 1, day: 1, hour: 14, minute: 2)

    static func microBreak() -> MicroBreak {
        MicroBreak(
            id: UUID(),
            blocks: [RoutineBlock(movement: armCircles, seconds: 60, trimmedFrom: nil)],
            emphasis: .circulation
        )
    }

    /// CIR-06 from the bundled library. The literal is the fallback for a snapshot run whose
    /// bundle cannot be read, so a missing resource produces a wrong-looking PNG rather than a
    /// crash in the middle of `make snapshots`.
    static let armCircles: Movement = {
        if let library = try? LibraryLoader.loadBundled(), let movement = library.movement(id: "CIR-06") {
            return movement
        }
        return Movement(
            id: "CIR-06",
            name: "Arm circles",
            bucket: .cir,
            bucketName: "Blood flow & circulation",
            regions: [.shoulder],
            dose: "30 s each way",
            perSide: false,
            blockSeconds: 60,
            difficulty: 1,
            settings: [.stand],
            equipmentOptional: [],
            microEligible: true,
            counteracts: "shoulder stiffness, upper-body circulation",
            instructions: """
                Arms straight out to the sides, make small circles forward and gradually enlarge \
                them until they're as big as your shoulders allow. Reverse direction and repeat. \
                Keep the ribs down and the neck relaxed.
                """
        )
    }()
}

/// The menu-bar states the snapshots render, frozen at the moments the handoff draws:
/// 32 minutes to a Hip reset, a 42-minute pause, and a Saturday.
extension SnapshotFixtures {
    static let menuStats = DailyStats(done: 3, snoozed: 1, skipped: 1, longestBoutSeconds: 72 * 60)
    static let menuOffHoursStats = DailyStats(done: 6, snoozed: 2, skipped: 1, longestBoutSeconds: 95 * 60)

    static func menuSitting() -> MenuBarState {
        var state = MenuBarState()
        state.mode = .sitting
        state.minutesRemaining = 32
        // 32 of a 55-minute bout left.
        state.elapsedFraction = 1 - 32.0 / 55
        state.title = MenuBarState.title(mode: .sitting, minutesRemaining: 32)
        state.subtitle = "\(routineName) · \(routineFocus)"
        state.stats = MenuBarState.statsLine(day: "Today", stats: menuStats)
        state.longestBout = MenuBarState.longestBoutLine(seconds: menuStats.longestBoutSeconds)
        return state
    }

    static func menuPaused() -> MenuBarState {
        var state = MenuBarState()
        state.mode = .paused
        state.minutesRemaining = 42
        state.title = MenuBarState.title(mode: .paused, minutesRemaining: 42)
        state.subtitle = MenuBarState.pausedSubtitle(resumesAt: menuResumeAt, remainingMinutes: 23)
        state.stats = MenuBarState.statsLine(day: "Today", stats: menuStats)
        state.longestBout = MenuBarState.longestBoutLine(seconds: menuStats.longestBoutSeconds)
        return state
    }

    static func menuOffHours() -> MenuBarState {
        var state = MenuBarState()
        state.mode = .offHours
        state.title = MenuBarState.title(mode: .offHours, minutesRemaining: 0)
        state.subtitle = MenuBarState.offHoursSubtitle(nextStart: menuMondayNine, now: menuSaturday)
        state.stats = MenuBarState.statsLine(day: "Friday", stats: menuOffHoursStats)
        state.longestBout = MenuBarState.longestBoutLine(seconds: menuOffHoursStats.longestBoutSeconds)
        return state
    }

    /// 15:00, when the paused countdown picks up again.
    static let menuResumeAt = menuDate(month: 9, day: 11, hour: 15)
    /// Saturday 12 September 2026, and the Monday morning that follows it.
    static let menuSaturday = menuDate(month: 9, day: 12, hour: 10, minute: 41)
    static let menuMondayNine = menuDate(month: 9, day: 14, hour: 9)

    static func menuDate(month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? panelInstant
    }
}

/// The settings window as the handoff draws it: a kettlebell to hand, Moderate, three movements
/// excluded, upper-back focus, two fullscreen exceptions and a three-minute away threshold.
@MainActor
extension SnapshotFixtures {
    /// A defaults suite of its own, wiped on every render so the PNGs never drift with use.
    static let settingsSuite = "movez.snapshots"

    static let excludedFixtureIds = ["FLX-03", "STR-07", "BAL-12"]
    static let exceptionFixtureIds = ["com.apple.iWork.Keynote", "us.zoom.xos"]

    static func settingsViewModel(
        sheet: SettingsViewModel.Sheet? = nil,
        preset: PresetId = .fiftyFiveFive,
        search: String = ""
    ) -> SettingsViewModel? {
        guard let library = try? LibraryLoader.loadBundled() else { return nil }

        UserDefaults().removePersistentDomain(forName: settingsSuite)
        let settings = SettingsStore(defaults: UserDefaults(suiteName: settingsSuite) ?? .standard)
        settings.preset = preset
        settings.customSitMinutes = 45
        // Band is what the handoff shows filled; the kettlebell is the intake's example.
        settings.equipment = [.band, .kettlebellOrDumbbell]
        settings.difficultyCap = 2
        settings.excludedMovementIds = Set(excludedFixtureIds)
        settings.focus = .moreUpperBack
        settings.fullscreenExceptions = exceptionFixtureIds
        settings.awayThresholdMinutes = 3

        let viewModel = SettingsViewModel(
            settings: settings,
            library: library,
            launchAtLogin: FakeLaunchAtLogin()
        )
        viewModel.librarySearch = search
        viewModel.hoursDraft = settings.workingHours
        viewModel.openSheet = sheet
        return viewModel
    }
}

/// The debug tools with something in them: a morning's worth of transitions, a held microphone,
/// and the clock running at sixty times.
@MainActor
extension SnapshotFixtures {
    /// 09:00 on the fixture's Friday, which every transition below hangs off.
    static let debugMorning = menuDate(month: 9, day: 11, hour: 9)

    static func debugState() -> DebugState {
        var snapshot = SchedulerSnapshot(now: debugMorning, dayKey: "2026-09-11")
        snapshot.state = .sitting
        snapshot.nextFullDueAt = debugMorning.addingTimeInterval(55 * 60)
        snapshot.nextMicroDueAt = debugMorning.addingTimeInterval(30 * 60)
        snapshot.lastCompletedBreakAt = debugMorning.addingTimeInterval(-5 * 60)
        snapshot.doneToday = 3
        snapshot.snoozedToday = 1
        snapshot.skipsToday = 1
        for transition in debugTransitions { snapshot.transitions.append(transition) }

        var state = DebugState()
        state.timeScale = 60
        state.rows = DebugViewModel.rows(DebugViewModel.InspectorInput(
            snapshot: snapshot,
            now: debugMorning.addingTimeInterval(23 * 60),
            snoozesLeft: 2,
            polling: true,
            pollCount: 412,
            overrides: "mic=on"
        ))
        state.transitions = snapshot.transitions.newestFirst
            .map { $0.line(formatter: TransitionLog.timeFormatter) }
        return state
    }

    /// Nine transitions: a morning that ran, was interrupted by a call, and recovered.
    static var debugTransitions: [Transition] {
        func step(_ minutes: Double, _ from: SchedulerState, _ to: SchedulerState, _ reason: String) -> Transition {
            Transition(at: debugMorning.addingTimeInterval(minutes * 60), from: from, to: to, reason: reason)
        }
        let anchor = debugMorning
        let pending = SchedulerState.pendingFull(since: anchor)
        let headsUp = SchedulerState.headsUp(startedAt: anchor, deferredSince: nil)
        let breaking = SchedulerState.fullBreak(startedAt: anchor)
        let countIn = SchedulerState.microCountIn(startedAt: anchor)
        let running = SchedulerState.microRunning(startedAt: anchor)
        let call = SchedulerState.suppressed(since: anchor, deferredFullDue: nil)

        return [
            step(0, .offHours, .sitting, "working hours started"),
            step(55, .sitting, pending, "full break due"),
            step(55.2, pending, headsUp, "input paused for 12 s"),
            step(56.2, headsUp, breaking, "heads-up elapsed"),
            step(61, breaking, .sitting, "break completed"),
            step(91, .sitting, countIn, "micro-break due"),
            step(91.5, countIn, running, "micro-break started"),
            step(92.5, running, .sitting, "micro-break finished"),
            step(104, .sitting, call, "call or screen share")
        ]
    }

    static func debugSettingsViewModel() -> SettingsViewModel? {
        guard let viewModel = settingsViewModel() else { return nil }
        viewModel.settings.debugExpanded = true
        viewModel.debug = debugState()
        return viewModel
    }
}
