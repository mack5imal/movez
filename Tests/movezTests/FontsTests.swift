import AppKit
import XCTest
@testable import movez

final class FontsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MovezFont.register()
    }

    func testEveryTextStyleResolvesToManrope() {
        XCTAssertEqual(MovezType.all.count, 42)
        for entry in MovezType.all {
            let font = entry.style.nsFont
            XCTAssertEqual(font.familyName, "Manrope", "\(entry.name) fell back to \(font.familyName ?? "nil")")
            XCTAssertEqual(font.pointSize, entry.style.size, accuracy: 0.01, entry.name)
        }
    }

    func testWeightsAreDistinct() {
        let regular = MovezFont.nsFont(40, weight: .regular)
        let bold = MovezFont.nsFont(40, weight: .bold)
        XCTAssertEqual(regular.familyName, "Manrope")
        XCTAssertEqual(bold.familyName, "Manrope")
        let regularWidth = ("March in place" as NSString).size(withAttributes: [.font: regular]).width
        let boldWidth = ("March in place" as NSString).size(withAttributes: [.font: bold]).width
        XCTAssertGreaterThan(boldWidth, regularWidth, "the variable weight axis is not being applied")
    }

    func testTrackingAndLineSpacingConvertFromEm() {
        // The handoff writes tracking in em; the app needs points.
        XCTAssertEqual(MovezType.eyebrowOverlay.tracking, 1.8, accuracy: 0.001)
        XCTAssertEqual(MovezType.overlayName.tracking, -2.8, accuracy: 0.001)
        XCTAssertEqual(MovezType.discNumerals.tracking, -3.36, accuracy: 0.001)
        // lineSpacing is the gap between line boxes, so a 28 pt / 1.45 paragraph asks for
        // 40.6 pt of line box and the font already supplies most of it.
        let instruction = MovezType.instruction
        let naturalLineBox = instruction.nsFont.ascender - instruction.nsFont.descender + instruction.nsFont.leading
        XCTAssertEqual(instruction.lineSpacing, 28 * 1.45 - naturalLineBox, accuracy: 0.001)
        XCTAssertGreaterThan(instruction.lineSpacing, 0)
        XCTAssertLessThan(instruction.lineSpacing, 28 * 0.45, "the font's own line box already covers part of it")
        XCTAssertEqual(MovezType.overlayName.lineSpacing, 0, accuracy: 0.001)
    }

    /// SwiftUI can only add space between lines, never take it away, so a line height under the
    /// font's own line box is silently set at the font's. A style asks for 1 (the font's natural
    /// line) or for at least that ratio, so that every line height written down is one that is
    /// drawn (UI-14, DECISIONS 85).
    func testEveryLineHeightIsOneOrAtLeastTheFontsNaturalRatio() {
        for entry in MovezType.all {
            let style = entry.style
            let font = style.nsFont
            let natural = (font.ascender - font.descender + font.leading) / style.size
            guard style.lineHeight != 1 else { continue }
            XCTAssertGreaterThanOrEqual(
                style.lineHeight, natural,
                "\(entry.name) asks for \(style.lineHeight), tighter than Manrope's \(natural)"
            )
        }
    }

    func testTheDisplayStylesMatchTheHandoffSizes() {
        XCTAssertEqual(MovezType.overlayName.size, 80)
        XCTAssertEqual(MovezType.overlayNameSide.size, 56)
        XCTAssertEqual(MovezType.instruction.size, 28)
        XCTAssertEqual(MovezType.discNumerals.size, 84)
        XCTAssertEqual(MovezType.discLabel.size, 16)
        XCTAssertEqual(MovezType.panelTitle.size, 20)
        XCTAssertEqual(MovezType.panelBody.size, 13)
        XCTAssertEqual(MovezType.panelDisc.size, 17)
        XCTAssertEqual(MovezType.menuRow.size, 13)
        XCTAssertEqual(MovezType.menuTitle.size, 14)
        XCTAssertEqual(MovezType.sectionLabel.size, 11)
        XCTAssertEqual(MovezType.endTitle.size, 84)
        XCTAssertEqual(MovezType.eyebrowOverlay.uppercase, true)
        XCTAssertEqual(MovezType.sectionLabel.uppercase, true)
    }

    func testEverySnapshotSurfaceHasASize() {
        for surface in SnapshotSurface.allCases {
            XCTAssertGreaterThan(surface.size.width, 0, surface.rawValue)
            XCTAssertGreaterThan(surface.size.height, 0, surface.rawValue)
        }
        XCTAssertTrue(SnapshotSurface.allCases.map(\.rawValue).contains("gallery"))
    }
}
