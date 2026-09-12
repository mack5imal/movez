import XCTest
@testable import movez

final class SubstitutionsTests: XCTestCase {
    private static let library: MovementLibrary = {
        do {
            return try LibraryLoader.loadBundled()
        } catch {
            fatalError("Bundled movement library failed to load: \(error)")
        }
    }()

    private var library: MovementLibrary { Self.library }

    private func peers(_ id: String) throws -> [String] {
        let movement = try XCTUnwrap(library.movement(id: id))
        return Substitutions.bodyweightPeers(for: movement, in: library).map(\.id)
    }

    func testExplicitRule6Swaps() throws {
        XCTAssertEqual(try peers("STR-09").first, "STR-04")
        XCTAssertEqual(try peers("CIR-18").first, "CIR-12")
        XCTAssertEqual(try peers("STR-17"), ["FLX-18", "STR-16"])
    }

    func testEveryEquipmentMovementHasABodyweightPeer() throws {
        let equipmentMovements = library.movements.filter(\.needsEquipment)
        XCTAssertEqual(equipmentMovements.count, 18)
        for movement in equipmentMovements {
            let peers = Substitutions.bodyweightPeers(for: movement, in: library)
            XCTAssertFalse(peers.isEmpty, "\(movement.id) has no bodyweight peer")
            for peer in peers {
                XCTAssertFalse(peer.needsEquipment, "peer \(peer.id) for \(movement.id) also needs equipment")
                XCTAssertNotEqual(peer.id, movement.id)
            }
            XCTAssertNotNil(Substitutions.bodyweightPeer(for: movement, library: library))
        }
    }

    func testPeersSharePurposeOrRegion() throws {
        for movement in library.movements.filter(\.needsEquipment) {
            let best = try XCTUnwrap(Substitutions.bodyweightPeer(for: movement, library: library))
            let sharesPurpose = best.counteracts == movement.counteracts
            let sharesRegion = !best.sharedRegions(with: movement).isEmpty
            XCTAssertTrue(sharesPurpose || sharesRegion, "\(movement.id) -> \(best.id) shares neither purpose nor region")
        }
    }

    func testFootRollerFallsBackAcrossBuckets() throws {
        // FLX-38 is the only foot-roller movement and has no equipment-free peer inside FLX.
        let peers = try peers("FLX-38")
        XCTAssertFalse(peers.isEmpty)
        let best = try XCTUnwrap(library.movement(id: peers[0]))
        XCTAssertTrue(best.regions.contains(.footShin))
    }

    func testBodyweightMovementsHaveNoPeers() throws {
        let movement = try XCTUnwrap(library.movement(id: "FLX-01"))
        XCTAssertTrue(Substitutions.bodyweightPeers(for: movement, in: library).isEmpty)
        XCTAssertNil(Substitutions.bodyweightPeer(for: movement, library: library))
    }

    func testResolveKeepsMovementWhenEquipmentIsOwned() throws {
        let banded = try XCTUnwrap(library.movement(id: "STR-17"))
        XCTAssertEqual(Substitutions.resolve(banded, owned: [.band], in: library).id, "STR-17")
        XCTAssertEqual(Substitutions.resolve(banded, owned: [], in: library).id, "FLX-18")
        XCTAssertEqual(Substitutions.resolve(banded, owned: [.ball], in: library).id, "FLX-18")
    }
}
