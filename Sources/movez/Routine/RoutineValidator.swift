import Foundation

/// Checks a routine against the rules every generated break must meet. An empty result means the
/// routine is valid.
///
/// The strict contract: five blocks, a circulation warm-up first, balance, flexibility and strength
/// in any order, then a hand, eye or breathing closer, each block exactly a minute.
/// `allowSampleShapes` relaxes all of that to "opens on circulation, three to six blocks of 20 to
/// 90 s" for the worked examples R1–R9 in the library document, which predate these rules.
enum RoutineValidator {
    static let blockCount = 5

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
        let count = routine.blocks.count
        if allowSampleShapes {
            guard count < 3 || count > 6 else { return [] }
            return ["block count \(count) is outside 3…6"]
        }
        guard count != blockCount else { return [] }
        return ["block count \(count) is not \(blockCount)"]
    }

    private static func orderProblems(_ routine: Routine, allowSampleShapes: Bool) -> [String] {
        let buckets = routine.buckets
        var problems: [String] = []
        if buckets.first != .cir {
            problems.append("first block is not a circulation movement")
        }
        guard !allowSampleShapes, buckets.count == blockCount else { return problems }

        let working = Array(buckets[1...3])
        if Set(working) != Set(RoutineBuilder.workingBuckets) || working.count != Set(working).count {
            let found = working.map(\.rawValue).joined(separator: ", ")
            problems.append("blocks 2–4 are \(found), expected one each of BAL, FLX and STR")
        }
        if let last = buckets.last, !Routine.closers.contains(last) {
            problems.append("block 5 is \(last.rawValue), expected HWF, EYE or BRE")
        }
        return problems
    }

    private static func durationProblems(_ routine: Routine, allowSampleShapes: Bool) -> [String] {
        routine.blocks.compactMap { block in
            if allowSampleShapes {
                guard block.seconds < 20 || block.seconds > 90 else { return nil }
                return "\(block.movement.id) runs \(block.seconds) s, outside the 20…90 s sample range"
            }
            guard block.seconds != Routine.blockSeconds else { return nil }
            return "\(block.movement.id) runs \(block.seconds) s, not \(Routine.blockSeconds) s"
        }
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
