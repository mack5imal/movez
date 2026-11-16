import XCTest
@testable import movez

/// A strength bucket's difficulty-3 moves unlock after five difficulty-2 completions in it (S9).
final class StrengthUnlockTests: XCTestCase {
    private static let library: StrengthLibrary = {
        do {
            return try StrengthLibraryLoader.loadBundled(movementLibrary: RoutineTestSupport.library)
        } catch {
            fatalError("Bundled strength library failed to load: \(error)")
        }
    }()

    private var library: StrengthLibrary { Self.library }

    private func ids(_ bucket: StrengthBucket, difficulty: Int) -> [String] {
        library.movements(in: bucket).filter { $0.difficulty == difficulty }.map(\.id)
    }

    /// Completions spread across the bucket's difficulty-2 moves, as a rotation would serve them.
    private func completions(_ bucket: StrengthBucket, count: Int) -> [MovementCompletion] {
        let pool = ids(bucket, difficulty: 2)
        return (0..<count).map { index in
            MovementCompletion(
                movementId: pool[index % pool.count],
                at: SchedulerHarness.mondayMorning.addingTimeInterval(Double(index) * 86_400),
                seconds: 45,
                routineId: UUID()
            )
        }
    }

    func testFourHingeCompletionsLeaveItsHardestMovesLockedAndFiveUnlockThem() throws {
        let hingeThree = Set(ids(.hng, difficulty: 3))
        let pushThree = Set(ids(.psh, difficulty: 3))
        XCTAssertFalse(hingeThree.isEmpty)
        XCTAssertFalse(pushThree.isEmpty)

        let four = StrengthUnlock.unlockedBuckets(library: library, completions: completions(.hng, count: 4))
        XCTAssertFalse(four.contains(.hng), "four is one short")

        let five = StrengthUnlock.unlockedBuckets(library: library, completions: completions(.hng, count: 5))
        XCTAssertEqual(five, [.hng], "five in total, across different moves, unlock the bucket, and push has earned nothing")
    }

    func testOnlyDifficultyTwoCompletionsCount() {
        let easy = ids(.hng, difficulty: 1)
        let completions = (0..<10).map { index in
            MovementCompletion(movementId: easy[index % easy.count], at: SchedulerHarness.mondayMorning, seconds: 45, routineId: nil)
        }
        XCTAssertTrue(StrengthUnlock.unlockedBuckets(library: library, completions: completions).isEmpty)
    }

    func testMovementModeCompletionsUnlockNothingInStrength() {
        let completions = (0..<10).map { _ in
            MovementCompletion(movementId: "STR-02", at: SchedulerHarness.mondayMorning, seconds: 60, routineId: nil)
        }
        XCTAssertTrue(StrengthUnlock.unlockedBuckets(library: library, completions: completions).isEmpty)
    }
}
