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
    static let toastRemaining: TimeInterval = 3.6

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
            startedAt: clock.now.addingTimeInterval(toastRemaining - 6),
            totalSeconds: 6
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
    static let toastNextBreak: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        components.hour = 14
        components.minute = 2
        return Calendar.current.date(from: components) ?? panelInstant
    }()

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
