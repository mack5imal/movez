import Foundation

/// One move of a micro-break as the panel shows it, whichever library it came from.
///
/// The panel only needs a name, an instruction, an optional dose and the move's timing, so both
/// kinds of micro-break are reduced to this rather than the panel learning two block types.
struct MicroPanelMove: Equatable {
    let name: String
    let instructions: String
    /// The library dose as the panel shows it. Movement-mode moves have no dose, so it is nil there
    /// and the panel draws no dose line.
    let dose: DoseText?
    let perSide: Bool
    let seconds: Int
    /// Done in a chair, which is what the count-in's posture words are made from.
    let seated: Bool

    /// Seconds given to each side of a per-side move.
    var secondsPerSide: Int { perSide ? seconds / 2 : seconds }
}

/// A micro-break as the panel runs it: its moves, each after a five-second lead-in, and the words
/// that depend on which library built it.
struct MicroPanelBreak: Equatable {
    let moves: [MicroPanelMove]
    /// The count-in's posture: "seated" or "standing" for Movement, as before; "sitting",
    /// "standing" or "sitting then standing" for Strength, as the design writes it.
    let posture: String
    /// A strength per-side move must tell the user when to change sides, because the side switches
    /// at the halfway chime; Movement's instructions are shown as they were.
    let switchesAtChime: Bool

    static let switchAtChime = "Switch at the chime."

    /// 65 s for one move, 70 s for two, lead-ins included.
    var totalSeconds: Int {
        moves.reduce(0) { $0 + Routine.leadInSeconds + $1.seconds }
    }

    /// Seconds into the running micro-break at which each move appears; its lead-in starts there.
    func appearsAt(move index: Int) -> Int {
        moves.prefix(index).reduce(0) { $0 + Routine.leadInSeconds + $1.seconds }
    }

    /// Seconds into the running micro-break at which each move starts.
    func startsAt(move index: Int) -> Int {
        appearsAt(move: index) + Routine.leadInSeconds
    }

    /// The instruction the panel shows for a move. Most strength instructions already end by saying
    /// which limb to switch at the chime, and those are left alone rather than said twice.
    func instructions(for move: MicroPanelMove) -> String {
        guard switchesAtChime, move.perSide, !move.instructions.localizedCaseInsensitiveContains("chime") else {
            return move.instructions
        }
        return "\(move.instructions) \(Self.switchAtChime)"
    }
}

extension MicroPanelBreak {
    /// A Movement micro-break, worded exactly as the panel worded it before modes existed.
    init(_ micro: MicroBreak) {
        moves = micro.blocks.map { block in
            MicroPanelMove(
                name: block.movement.name,
                instructions: block.movement.instructions,
                dose: nil,
                perSide: block.perSide,
                seconds: block.seconds,
                seated: block.movement.settings == [.chair]
            )
        }
        // A micro-break whose movements can only be done in a chair is done seated; one with
        // anything that can be done standing is standing.
        posture = !moves.isEmpty && moves.allSatisfy(\.seated) ? "seated" : "standing"
        switchesAtChime = false
    }

    /// A strength micro-break: END moves, each with its dose under its name.
    init(_ micro: StrengthMicroBreak) {
        moves = micro.blocks.map { block in
            MicroPanelMove(
                name: block.movement.name,
                instructions: block.movement.instructions,
                dose: DoseText(block.movement.dose),
                perSide: block.perSide,
                seconds: block.seconds,
                seated: StrengthPosture(block.movement) == .seated
            )
        }
        posture = Self.strengthPosture(moves.map(\.seated))
        switchesAtChime = true
    }

    init(_ planned: PlannedMicro) {
        switch planned {
        case let .movement(micro): self.init(micro)
        case let .strength(micro): self.init(micro)
        }
    }

    /// "sitting", "standing" or "sitting then standing". S7 keeps both moves in one posture, so the
    /// mixed phrase only appears if that rule is ever let go of; a move order the design never
    /// draws (standing, then sitting) reads by its first move.
    static func strengthPosture(_ seated: [Bool]) -> String {
        guard let first = seated.first else { return "standing" }
        if seated.allSatisfy({ $0 }) { return "sitting" }
        return first ? "sitting then standing" : "standing"
    }
}
