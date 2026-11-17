import XCTest
@testable import movez

/// A move served in either mode is not served again that day in either mode (S8).
final class CrossModeUsageTests: XCTestCase {
    private static let strengthLibrary: StrengthLibrary = {
        do {
            return try StrengthLibraryLoader.loadBundled(movementLibrary: RoutineTestSupport.library)
        } catch {
            fatalError("Bundled strength library failed to load: \(error)")
        }
    }()

    private let movementLibrary = RoutineTestSupport.library
    private var strengthLibrary: StrengthLibrary { Self.strengthLibrary }
    private var usage: CrossModeUsage {
        CrossModeUsage(movementLibrary: movementLibrary, strengthLibrary: strengthLibrary)
    }

    /// A real `same` pair whose movement-library side belongs to a family with other members, read
    /// out of the libraries rather than assumed (HNG-01 and STR-01 in the current files).
    private struct SamePair {
        let strength: String
        let movement: String
        let familyMates: [String]
    }

    private func sameOverlapInAFamily() throws -> SamePair {
        for move in strengthLibrary.movements {
            guard let overlap = move.v4Overlap, overlap.kind == .same,
                  let counterpart = movementLibrary.movements.first(where: { $0.id == overlap.id }),
                  let family = counterpart.family else { continue }
            let mates = movementLibrary.movements.filter { $0.family == family && $0.id != counterpart.id }.map(\.id)
            if !mates.isEmpty { return SamePair(strength: move.id, movement: counterpart.id, familyMates: mates) }
        }
        throw XCTSkip("the libraries have no same overlap inside a family")
    }

    private func similarOverlap() throws -> (strength: String, movement: String) {
        guard let move = strengthLibrary.movements.first(where: { $0.v4Overlap?.kind == .similar }),
              let overlap = move.v4Overlap else {
            throw XCTSkip("the strength library has no similar overlap")
        }
        return (move.id, overlap.id)
    }

    func testTheLibrariesCarryTheNamedPair() {
        XCTAssertEqual(strengthLibrary.movement(id: "HNG-01")?.v4Overlap, StrengthOverlap(id: "STR-01", kind: .same))
    }

    func testNothingServedLeavesEverythingEligible() {
        XCTAssertEqual(usage.used(movementIds: [], strengthIds: []), CrossModeUsage.Used())
    }

    func testAMovementServedExcludesItsSameStrengthCounterpart() throws {
        let pair = try sameOverlapInAFamily()
        let used = usage.used(movementIds: [pair.movement], strengthIds: [])
        XCTAssertTrue(used.strengthIds.contains(pair.strength), "\(pair.movement) served excludes \(pair.strength)")
        XCTAssertTrue(used.movementIds.isSuperset(of: pair.familyMates), "and its family stays used")
    }

    func testAStrengthMoveServedExcludesItsSameMovementAndThatMovementsFamily() throws {
        let pair = try sameOverlapInAFamily()
        let used = usage.used(movementIds: [], strengthIds: [pair.strength])
        XCTAssertTrue(used.movementIds.contains(pair.movement), "\(pair.strength) served excludes \(pair.movement)")
        XCTAssertTrue(used.movementIds.isSuperset(of: pair.familyMates), "and every member of its family")
        XCTAssertTrue(used.strengthIds.contains(pair.strength))
    }

    func testAFamilyMateServedExcludesTheStrengthMoveThatIsSameAsAnotherMember() throws {
        let pair = try sameOverlapInAFamily()
        let mate = try XCTUnwrap(pair.familyMates.first)
        let used = usage.used(movementIds: [mate], strengthIds: [])
        XCTAssertTrue(used.movementIds.contains(pair.movement))
        XCTAssertTrue(
            used.strengthIds.contains(pair.strength),
            "\(mate) shares a family with \(pair.movement), which is the same as \(pair.strength)"
        )
    }

    func testASimilarOverlapExcludesNothingInEitherDirection() throws {
        let pair = try similarOverlap()
        let fromMovement = usage.used(movementIds: [pair.movement], strengthIds: [])
        XCTAssertFalse(fromMovement.strengthIds.contains(pair.strength), "similar is different enough to share a day")

        let fromStrength = usage.used(movementIds: [], strengthIds: [pair.strength])
        XCTAssertFalse(fromStrength.movementIds.contains(pair.movement))
        XCTAssertEqual(fromStrength.strengthIds, [pair.strength])
    }

    func testAStrengthMoveWithNoOverlapOnlyExcludesItself() throws {
        let plain = try XCTUnwrap(strengthLibrary.movements.first { $0.v4Overlap == nil })
        let used = usage.used(movementIds: [], strengthIds: [plain.id])
        XCTAssertEqual(used, CrossModeUsage.Used(movementIds: [], strengthIds: [plain.id]))
    }
}
