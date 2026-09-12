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
