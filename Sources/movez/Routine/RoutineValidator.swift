import Foundation

/// Checks a routine against the chaining rules. An empty result means the routine is valid.
///
/// The strict mode is the contract every generated routine must meet. `allowSampleShapes` relaxes
/// block count and ordering for the worked examples R1–R9 in the library document, which predate
/// the four-block default and run to six blocks.
enum RoutineValidator {
    static func validate(
        _ routine: Routine,
        library: MovementLibrary,
        excluded: Set<String> = [],
        allowSampleShapes: Bool = false
    ) -> [String] {
        var problems: [String] = []
        problems += blockCountProblems(routine, allowSampleShapes: allowSampleShapes)
        problems += orderProblems(routine, allowSampleShapes: allowSampleShapes)
        problems += durationProblems(routine, allowSampleShapes: allowSampleShapes)
        problems += membershipProblems(routine, library: library, excluded: excluded)
        return problems
    }

    private static func blockCountProblems(_ routine: Routine, allowSampleShapes: Bool) -> [String] {
        let maximum = allowSampleShapes ? 6 : 5
        guard routine.blocks.count < 3 || routine.blocks.count > maximum else { return [] }
        return ["block count \(routine.blocks.count) is outside 3…\(maximum)"]
    }

    private static func orderProblems(_ routine: Routine, allowSampleShapes: Bool) -> [String] {
        guard !allowSampleShapes else {
            guard routine.blocks.first?.movement.bucket != .cir else { return [] }
            return ["first block is not a circulation movement"]
        }

        let plan = routine.shape.plan(count: routine.blocks.count)
        guard plan.count == routine.blocks.count else {
            return ["shape \(routine.shape.rawValue) has no plan for \(routine.blocks.count) blocks"]
        }
        return zip(plan, routine.blocks).enumerated().compactMap { index, pair in
            let (allowed, block) = pair
            guard !allowed.contains(block.movement.bucket) else { return nil }
            let expected = allowed.map(\.rawValue).joined(separator: "|")
            return "block \(index + 1) is \(block.movement.bucket.rawValue), expected \(expected)"
        }
    }

    private static func durationProblems(_ routine: Routine, allowSampleShapes: Bool) -> [String] {
        var problems: [String] = []
        let total = routine.totalSeconds
        if total < RoutineBuilder.minTotalSeconds || total > RoutineBuilder.maxTotalSeconds {
            problems.append("total \(total) s is outside \(RoutineBuilder.minTotalSeconds)…\(RoutineBuilder.maxTotalSeconds) s")
        }
        for block in routine.blocks {
            let natural = block.movement.blockSeconds
            // A block never runs longer than the movement's natural dose. It may be trimmed, but
            // only down to 60 s — and a movement whose natural block is already shorter than 60 s
            // (a 30 s eye break, say) is served at its natural length.
            let floor = allowSampleShapes ? 20 : min(RoutineBuilder.trimFloorSeconds, natural)
            if block.seconds > natural {
                problems.append("\(block.movement.id) runs \(block.seconds) s, longer than its natural \(natural) s")
            }
            if block.seconds < floor {
                problems.append("\(block.movement.id) runs \(block.seconds) s, below the \(floor) s floor")
            }
            if block.seconds > 90 {
                problems.append("\(block.movement.id) runs \(block.seconds) s, above the 90 s block ceiling")
            }
        }
        return problems
    }

    private static func membershipProblems(
        _ routine: Routine,
        library: MovementLibrary,
        excluded: Set<String>
    ) -> [String] {
        var problems: [String] = []
        var seen = Set<String>()
        for block in routine.blocks {
            let id = block.movement.id
            if library.movement(id: id) == nil {
                problems.append("\(id) is not in the library")
            }
            if excluded.contains(id) {
                problems.append("\(id) is excluded but was served")
            }
            if !seen.insert(id).inserted {
                problems.append("\(id) appears twice in one routine")
            }
        }
        return problems
    }
}
