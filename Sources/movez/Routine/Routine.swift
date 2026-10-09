import Foundation

/// One movement in a generated routine, with the seconds it is actually given.
struct RoutineBlock: Hashable, Identifiable {
    let movement: Movement
    let seconds: Int

    var id: String { movement.id }
    var perSide: Bool { movement.perSide }

    /// Seconds given to each side of a per-side movement.
    var secondsPerSide: Int { perSide ? seconds / 2 : seconds }
}

/// A generated full break: a circulation warm-up, then balance, flexibility and strength in a
/// random order, then a closer to come back to the desk on.
///
/// It has no name. The movements are drawn at random, so a title could only describe whichever
/// region the draw happened to land on, and naming by region put "Hip reset" over about a third
/// of all routines, because the hip region set is the broadest one in the library.
struct Routine: Hashable, Identifiable {
    let id: UUID
    let blocks: [RoutineBlock]

    /// Every movement runs for a minute, a per-side one thirty seconds a side. The library's own
    /// `block_seconds` varies from 20 to 90 s, and fitting a five-minute budget around it took a
    /// repair pass that quietly favoured long movements over short ones.
    static let blockSeconds = 60

    /// The lead-in before each movement, the first included: a moment to read what is coming
    /// before the clock starts.
    static let leadInSeconds = 5

    /// The buckets the last block is drawn from, as one pool.
    static let closers: Set<Bucket> = [.hwf, .eye, .bre]

    /// Movement time plus a lead-in before every movement.
    var totalSeconds: Int {
        movementSeconds + Self.leadInSeconds * blocks.count
    }

    var movementSeconds: Int { blocks.reduce(0) { $0 + $1.seconds } }
    var movementIds: [String] { blocks.map(\.movement.id) }
    var buckets: [Bucket] { blocks.map(\.movement.bucket) }

    /// The regions worked by the strength block, carried into the next break so the same region
    /// is not loaded twice in a row.
    var strengthRegions: Set<Region> {
        let strength = blocks.first { $0.movement.bucket == .str }
        return Set(strength?.movement.regions ?? [])
    }
}

/// A generated micro-break: one per-side movement for the whole minute, thirty seconds a side,
/// or two one-sided movements of thirty seconds each with a lead-in before the second.
struct MicroBreak: Hashable, Identifiable {
    let id: UUID
    let blocks: [RoutineBlock]

    /// 60 s for one movement, 65 s for two. The first movement needs no lead-in of its own: the
    /// count-in has already said what it is.
    var totalSeconds: Int {
        blocks.reduce(0) { $0 + $1.seconds } + Routine.leadInSeconds * max(0, blocks.count - 1)
    }

    var movementIds: [String] { blocks.map(\.movement.id) }

    /// Seconds into the running micro-break at which each block appears; the second one's
    /// lead-in starts there.
    func appearsAt(block index: Int) -> Int {
        let earlier = blocks.prefix(index).reduce(0) { $0 + $1.seconds }
        return earlier + Routine.leadInSeconds * max(0, index - 1)
    }

    /// Seconds into the running micro-break at which each block's movement starts.
    func startsAt(block index: Int) -> Int {
        appearsAt(block: index) + (index > 0 ? Routine.leadInSeconds : 0)
    }

    /// The blocks the user got at least halfway through in `seconds` of running time — the rule a
    /// full break is held to, applied to each movement.
    func blocksRun(seconds: Int) -> [RoutineBlock] {
        blocks.indices.filter { index in
            (seconds - startsAt(block: index)) * 2 >= blocks[index].seconds
        }.map { blocks[$0] }
    }

    /// "MICRO-BREAK · SHOULDERS", for the block on screen.
    static func eyebrow(for block: RoutineBlock?) -> String {
        "MICRO-BREAK · \(regionWord(for: block).uppercased())"
    }

    /// The plain-language region word taken from a movement's primary region.
    static func regionWord(for block: RoutineBlock?) -> String {
        guard let region = block?.movement.regions.first else { return "movement" }
        return regionWord(for: region)
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
