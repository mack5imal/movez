import Foundation

/// SplitMix64 — a tiny, stable PRNG.
///
/// The coordinator seeds the builder with `hash(day, breakIndex)` so a relaunch mid-day
/// regenerates exactly the same routine. That requires a generator whose output does not depend
/// on the standard library's version, which `SystemRandomNumberGenerator` does not promise.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var result = state
        result = (result ^ (result >> 30)) &* 0xBF58_476D_1CE4_E5B9
        result = (result ^ (result >> 27)) &* 0x94D0_49BB_1331_11EB
        return result ^ (result >> 31)
    }

    /// A number in `0..<1`, from the top 53 bits — the ones the generator mixes best.
    mutating func unitInterval() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// An index drawn in proportion to `weights`, or nil when there is nothing to draw from.
    ///
    /// Selection weights are fractional now that recency divides them, so the draw works in
    /// `Double` rather than counting integer tickets.
    mutating func weightedIndex(in weights: [Double]) -> Int? {
        let total = weights.reduce(0, +)
        guard total > 0 else { return nil }
        var ticket = unitInterval() * total
        for (index, weight) in weights.enumerated() {
            ticket -= weight
            if ticket < 0 { return index }
        }
        return weights.indices.last
    }

    /// `elements` in a random order. Fisher–Yates by hand rather than `shuffled(using:)`, whose
    /// algorithm the standard library does not promise to keep, so the order is as stable across
    /// releases as the generator itself.
    mutating func shuffled<Element>(_ elements: [Element]) -> [Element] {
        var result = elements
        guard result.count > 1 else { return result }
        for index in stride(from: result.count - 1, to: 0, by: -1) {
            let other = Int(next() % UInt64(index + 1))
            result.swapAt(index, other)
        }
        return result
    }

    /// A stable seed for a given day and break index. `hashValue` is not stable across launches,
    /// so the bytes are folded by hand.
    static func seed(day: String, index: Int) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in day.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        hash = (hash ^ UInt64(bitPattern: Int64(index))) &* 0x0000_0100_0000_01B3
        return hash
    }
}
