import Foundation

/// Which strength difficulty-3 moves the user has earned (S9).
///
/// Unlike movement mode, which unlocks a difficulty-3 movement through one difficulty-2 peer in the
/// same tissue, a strength pattern unlocks as a whole: five completions of any of its difficulty-2
/// moves in total. A strength pattern is a single movement skill, so practice on any of its
/// intermediate moves earns the harder versions of it, and no one difficulty-2 move has to be
/// served five times out of a rotation that deliberately spreads the draws.
enum StrengthUnlock {
    /// Shared with movement mode so that both modes ask for the same amount of practice.
    static let threshold = HistoryStore.difficultyUnlockThreshold

    /// The buckets whose difficulty-3 moves are unlocked by these completions.
    static func unlockedBuckets(library: StrengthLibrary, completions: [MovementCompletion]) -> Set<StrengthBucket> {
        var bucketById: [String: StrengthBucket] = [:]
        for movement in library.movements where movement.difficulty == 2 {
            bucketById[movement.id] = movement.bucket
        }
        var counts: [StrengthBucket: Int] = [:]
        for completion in completions {
            if let bucket = bucketById[completion.movementId] { counts[bucket, default: 0] += 1 }
        }
        return Set(counts.filter { $0.value >= threshold }.keys)
    }
}
