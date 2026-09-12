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
