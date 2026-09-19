import Foundation

/// The block shapes a generated routine can take. The standard shape is the chaining-rule
/// default; the wind-down is the documented variant for the last break of a working day (brief §6,
/// library §13 sample R6).
///
/// There is no wake-up shape any more. It applied to the first break of every calendar day, which
/// for anyone working odd hours is neither the start of their day nor a meaningful moment, and it
/// spent two of four blocks on circulation, so the twenty circulation movements carried half of
/// every such routine. Nor is there a post-lunch shape — see `Scheduler+Idle`.
enum RoutineShape: String, Hashable, Codable, CaseIterable {
    /// CIR → FLX → (STR | BAL) → closer
    case standard
    /// CIR → FLX → FLX → BRE — the last break unwinds and ends on breath.
    case windDown

    /// Buckets allowed at each position for a routine of `count` blocks.
    ///
    /// Four blocks is the chaining-rule default. The fifth block, when the four-block shape falls
    /// short of the 270 s floor, is an extra FLX inserted before the closer — the shape the
    /// library's own samples take (R2, R4, R7).
    func plan(count: Int) -> [[Bucket]] {
        var positions: [[Bucket]]
        switch self {
        case .standard: positions = [[.cir], [.flx], [.str, .bal]]
        case .windDown: positions = [[.cir], [.flx], [.flx]]
        }
        if count <= 3 { positions.removeLast() }
        if count >= 5 { positions.append([.flx]) }
        positions.append(self == .windDown ? [.bre] : Self.closers)
        return positions
    }

    /// The position of the strength-or-balance block, which carries the region the next break avoids.
    var strengthPosition: Int { 2 }

    static let closers: [Bucket] = [.hwf, .eye, .bre]

    static func shape(for timeOfDay: TimeOfDay) -> RoutineShape {
        switch timeOfDay {
        case .last: return .windDown
        case .mid, .normal: return .standard
        }
    }
}

/// One movement in a generated routine, with the seconds it is actually given.
struct RoutineBlock: Hashable, Identifiable {
    let movement: Movement
    let seconds: Int
    /// The movement's natural `block_seconds` when this block was shortened to fit the budget.
    let trimmedFrom: Int?

    var id: String { movement.id }
    var perSide: Bool { movement.perSide }
    var wasTrimmed: Bool { trimmedFrom != nil }

    /// Seconds given to each side of a per-side movement.
    var secondsPerSide: Int { perSide ? seconds / 2 : seconds }
}

/// A generated full break.
struct Routine: Hashable, Identifiable {
    let id: UUID
    let name: String
    let focus: String
    let completionTitle: String
    let slot: RotationSlot
    let shape: RoutineShape
    let timeOfDay: TimeOfDay
    let blocks: [RoutineBlock]

    /// Seconds between two blocks, used for the transition card and its chime.
    static let transitionSeconds = 5

    /// Block time plus the transitions between blocks.
    var totalSeconds: Int {
        blocks.reduce(0) { $0 + $1.seconds } + Self.transitionSeconds * max(0, blocks.count - 1)
    }

    var blockSeconds: Int { blocks.reduce(0) { $0 + $1.seconds } }
    var movementIds: [String] { blocks.map(\.movement.id) }
    var buckets: [Bucket] { blocks.map(\.movement.bucket) }

    /// "HIP RESET · HIPS AND GLUTES"
    var eyebrow: String { "\(name) · \(focus)".uppercased() }
    /// "Hip reset · hips and glutes"
    var subtitle: String { "\(name) · \(focus)" }

    /// The regions worked by the strength or balance block, carried into the next break so the
    /// same region is not loaded twice in a row.
    var strengthRegions: Set<Region> {
        let strength = blocks.first { $0.movement.bucket == .str || $0.movement.bucket == .bal }
        return Set(strength?.movement.regions ?? [])
    }
}

/// A generated micro-break: one 60 s block or two 30 s blocks.
struct MicroBreak: Hashable, Identifiable {
    let id: UUID
    let blocks: [RoutineBlock]
    let emphasis: MicroContext.Emphasis

    var totalSeconds: Int { blocks.reduce(0) { $0 + $1.seconds } }
    var movementIds: [String] { blocks.map(\.movement.id) }

    /// "MICRO-BREAK · SHOULDERS"
    var eyebrow: String { "MICRO-BREAK · \(regionWord.uppercased())" }

    /// The plain-language region word taken from the first movement's primary region.
    var regionWord: String {
        guard let region = blocks.first?.movement.regions.first else { return "movement" }
        return MicroBreak.regionWord(for: region)
    }

    static func regionWord(for region: Region) -> String {
        plainRegionWords[region] ?? region.rawValue.lowercased()
    }

    /// The plain-language name for each region, used in micro-break eyebrows.
    static let plainRegionWords: [Region: String] = [
        .shoulder: "shoulders",
        .neck: "neck",
        .calfAnkle: "calves",
        .eyes: "eyes",
        .wristForearm: "hands",
        .hip: "hips",
        .thoracic: "upper back",
        .breath: "breathing",
        .full: "whole body",
        .glute: "glutes",
        .hamstring: "hamstrings",
        .quad: "quads",
        .adductor: "inner thighs",
        .chest: "chest",
        .lumbarCore: "core",
        .footShin: "feet"
    ]
}
