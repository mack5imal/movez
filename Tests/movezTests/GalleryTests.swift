import XCTest
@testable import movez

/// The gallery is the reference page, so its samples have to be strips and discs a real surface
/// draws (UI-11).
@MainActor
final class GalleryTests: XCTestCase {
    func testTheStripSamplesHaveTheLengthsTheirLabelsSayAndUniqueIds() {
        let samples = GalleryView.stripSamples
        XCTAssertEqual(samples.map(\.items.count), [3, 4, 5, 5])
        for sample in samples {
            XCTAssertEqual(Set(sample.items.map(\.id)).count, sample.items.count, "\(sample.label): duplicate ids")
            XCTAssertTrue(sample.label.hasPrefix("\(sample.items.count) columns") || sample.allAccent, sample.label)
        }
    }

    func testTheSideSampleHalfFillsAPerSideBlock() throws {
        let sample = try XCTUnwrap(GalleryView.stripSamples.first { $0.label.contains("/side") })
        let current = try XCTUnwrap(sample.items.first { $0.state == .current })
        XCTAssertTrue(current.name.contains("/side"), current.name)
        XCTAssertEqual(current.sideIndex, 0)
    }

    /// The small discs carry the numeral style their surface passes, not the scaled default.
    func testTheSmallDiscSamplesUseTheirSurfacesNumeralStyles() {
        XCTAssertEqual(GalleryView.panelDiscSample.numeralStyle, MovezType.panelDisc)
        XCTAssertEqual(GalleryView.menuDiscSample.numeralStyle, MovezType.menuDisc)
    }
}
