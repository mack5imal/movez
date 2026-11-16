import XCTest
@testable import movez

/// The snapshot fixtures are how a UI change is reviewed, so a fixture that quietly draws the
/// wrong thing (an empty card, the wrong moment, another surface's picture) defeats the point.
/// `make snapshots` only checks that each PNG exists; these check what is in them (UI-12, UI-13).
@MainActor
final class SnapshotFixturesTests: XCTestCase {
    // MARK: - Every surface has its own fixture

    func testEverySurfaceHasAFixtureOfItsOwn() {
        let missing = SnapshotSurface.allCases.filter { SnapshotRenderer.fixtureView(for: $0) == nil }
        XCTAssertEqual(missing.map(\.rawValue), [], "surfaces that would render someone else's picture")
    }

    // MARK: - The strength overlay fixtures

    private struct OverlayFixture {
        var name: String
        var state: StrengthOverlayState
        /// The segment it was driven to; nil where it is the opening lead-in, which has none yet.
        var segment: StrengthSessionTimeline.Kind?
    }

    /// Each strength overlay fixture shows a move, at the segment it was driven to.
    func testEveryStrengthOverlayFixtureIsFilledInAtItsMoment() {
        let expected = [
            OverlayFixture(name: "set", state: SnapshotFixtures.strengthSet(), segment: .set(1)),
            OverlayFixture(name: "warm-up", state: SnapshotFixtures.strengthWarmUp(), segment: .warmUp),
            OverlayFixture(name: "lead-in", state: SnapshotFixtures.strengthLeadIn(), segment: .leadIn),
            OverlayFixture(name: "rest", state: SnapshotFixtures.strengthRest(), segment: .rest(beforeSet: 2)),
            OverlayFixture(name: "cool-down", state: SnapshotFixtures.strengthCoolDown(), segment: .coolDown),
            OverlayFixture(name: "side", state: SnapshotFixtures.strengthSide(), segment: .set(2)),
            OverlayFixture(name: "hold", state: SnapshotFixtures.strengthHold(), segment: .set(1)),
            OverlayFixture(name: "paused", state: SnapshotFixtures.strengthPaused(), segment: .set(1)),
            OverlayFixture(name: "reduced motion", state: SnapshotFixtures.strengthReducedMotion(), segment: .set(1)),
            OverlayFixture(name: "long dose", state: SnapshotFixtures.strengthLongDose(), segment: .set(1)),
            OverlayFixture(name: "relaxed", state: SnapshotFixtures.strengthRelaxed(), segment: .set(1)),
            OverlayFixture(name: "end-range", state: SnapshotFixtures.endRange(), segment: .block(1)),
            OverlayFixture(name: "end-range lead-in", state: SnapshotFixtures.endRangeLeadIn(), segment: nil),
            OverlayFixture(name: "end-range side", state: SnapshotFixtures.endRangeSide(), segment: .block(2)),
            OverlayFixture(name: "end-range paused", state: SnapshotFixtures.endRangePaused(), segment: .block(1))
        ]
        for fixture in expected {
            XCTAssertFalse(fixture.state.movementName.isEmpty, "\(fixture.name) draws an empty card")
            XCTAssertNotNil(fixture.state.segment, "\(fixture.name) ran past the end of its break")
            if let segment = fixture.segment {
                XCTAssertEqual(fixture.state.segment, segment, fixture.name)
            }
        }
    }

    // MARK: - The strength panel fixtures

    func testEveryStrengthMicroFixtureHasAMicroBreak() {
        let panels: [(name: String, model: PanelViewModel)] = [
            ("count-in", SnapshotFixtures.strengthMicroCountIn()),
            ("running", SnapshotFixtures.strengthMicroRunning()),
            ("side", SnapshotFixtures.strengthMicroRunning(elapsed: SnapshotFixtures.microSideElapsed, perSide: true)),
            ("long text", SnapshotFixtures.strengthMicroLongText())
        ]
        for panel in panels {
            let micro = panel.model.micro
            XCTAssertNotNil(micro, panel.name)
            XCTAssertFalse(micro?.moves.isEmpty ?? true, "\(panel.name) has no moves")
        }
    }

    /// The long-text panel is the tallest a strength micro-break can be: the longest standing
    /// END name over the longest END instruction a micro-break can serve.
    func testTheLongTextMicroDrawsTheLongestNameOverTheLongestInstruction() throws {
        let library = try XCTUnwrap(SnapshotFixtures.strengthLibrary)
        // What the micro builder can serve: END, micro-eligible, never on the floor (DECISIONS 67).
        let eligible = library.movements.filter { $0.bucket == .end && $0.microEligible && !$0.onFloor }
        let longestInstruction = try XCTUnwrap(eligible.max { $0.instructions.count < $1.instructions.count })
        let standing = eligible.filter { StrengthPosture($0) == .standing }
        let longestName = try XCTUnwrap(standing.max { $0.name.count < $1.name.count })

        let move = try XCTUnwrap(SnapshotFixtures.strengthMicroLongText().micro?.moves.first)
        XCTAssertEqual(move.instructions, longestInstruction.instructions)
        XCTAssertEqual(move.name, longestName.name)
        XCTAssertTrue(move.perSide, "per side, so the switch cue is appended too")
    }
}
