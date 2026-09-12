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
