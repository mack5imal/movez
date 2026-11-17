import XCTest
@testable import movez

/// The design's dose display rule.
final class DoseTextTests: XCTestCase {
    func testATwoSidedDoseIsVerbatim() {
        XCTAssertEqual(DoseText("12 reps"), DoseText(line: "12 reps", modifier: nil))
    }

    func testSideIsSpeltOut() {
        XCTAssertEqual(DoseText("10/side").line, "10 each side")
        XCTAssertEqual(DoseText("25 s/side").line, "25 s each side")
        XCTAssertNil(DoseText("25 s/side").modifier)
    }

    func testEachDirectionPerSideKeepsItsCommaOnTheDoseLine() {
        XCTAssertEqual(DoseText("2 each direction/side"), DoseText(line: "2 each direction, each side", modifier: nil))
    }

    func testTextAfterTheFirstCommaMovesToTheModifierLine() {
        XCTAssertEqual(
            DoseText("12 reps, alternating, 2 s hold"),
            DoseText(line: "12 reps", modifier: "Alternating · 2 s hold")
        )
        XCTAssertEqual(DoseText("4/side, 3 s hold"), DoseText(line: "4 each side", modifier: "3 s hold"))
    }

    func testEverythingElseIsVerbatim() {
        for dose in ["6 × 5 s", "8 slow reps", "30 s hold", "45–60 s"] {
            XCTAssertEqual(DoseText(dose), DoseText(line: dose, modifier: nil))
        }
    }

    /// Every dose in the bundled library reads without a stray "/side" or a trailing comma.
    func testEveryLibraryDoseDisplaysCleanly() {
        for movement in StrengthTestSupport.library.movements {
            let text = DoseText(movement.dose)
            XCTAssertFalse(text.line.contains("/side"), movement.id)
            XCTAssertFalse(text.line.isEmpty, movement.id)
            XCTAssertFalse(text.modifier?.contains(",") ?? false, movement.id)
        }
    }
}
