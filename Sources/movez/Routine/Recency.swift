import Foundation

/// How recently a movement has been served, expressed as a weight multiplier.
///
/// The chaining rules only ever looked at the day in front of them, so yesterday's movements were
/// exactly as likely as any other and the same few came round again and again. A movement served
/// in the last three days is therefore weighted down, most for yesterday, and is back to full
/// weight on the fourth day.
///
/// Distance is measured in whole calendar days rather than elapsed seconds on purpose: the menu
/// caches the routine it advertises, so a weight that drifted through the day would let the
/// overlay serve something other than what the menu promised.
enum Recency {
    /// How far back a serving is remembered.
    static let horizonDays = 3

    /// How much one serving that many days ago counts for.
    static func weight(daysAgo: Int) -> Double {
        guard daysAgo >= 1, daysAgo <= horizonDays else { return 0 }
        return Double(horizonDays - daysAgo + 1) / Double(horizonDays)
    }

    /// How hard the accumulated score bites. One serving yesterday leaves a third of the weight.
    static let strength = 2.0

    /// The multiplier for a movement with the given score. Never zero: a small pool that has all
    /// been served recently still has to produce a routine.
    static func multiplier(score: Double) -> Double {
        1 / (1 + strength * max(0, score))
    }
}
