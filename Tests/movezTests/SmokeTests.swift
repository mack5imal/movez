import AppKit
import XCTest
@testable import movez

final class SmokeTests: XCTestCase {
    func testManropeRegisters() {
        MovezFont.register()
        XCTAssertFalse(MovezFont.fontURLs().isEmpty, "No Manrope TTF found in the app bundle")
        XCTAssertTrue(
            NSFontManager.shared.availableFontFamilies.contains(MovezFont.familyName),
            "Manrope family is not available after registration"
        )
        let bold = MovezFont.nsFont(12, weight: .bold)
        XCTAssertTrue(
            bold.familyName == MovezFont.familyName,
            "Expected a Manrope face, resolved \(bold.familyName ?? "nil") instead"
        )
    }

    func testBundledChimesArePresent() throws {
        for name in ["headsup", "transition", "completion"] {
            let url = try XCTUnwrap(
                MovezBundle.resources.url(forResource: name, withExtension: "wav", subdirectory: "Chimes"),
                "Missing Chimes/\(name).wav in the app bundle"
            )
            let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
            XCTAssertGreaterThan(size, 10_000, "Chimes/\(name).wav is only \(size) bytes")
        }
    }

    func testMovementLibraryIsBundled() throws {
        let url = try XCTUnwrap(
            MovezBundle.resources.url(forResource: "movement-library-v4", withExtension: "json"),
            "Missing movement-library-v4.json in the app bundle"
        )
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 50_000)
    }

    func testLaunchArgumentParsing() {
        let arguments = LaunchArguments(["movez", "--snapshot", "gallery", "--out", "/tmp/a.png"])
        XCTAssertEqual(arguments.snapshot, "gallery")
        XCTAssertEqual(arguments.out, "/tmp/a.png")
        XCTAssertFalse(arguments.smoke)
        XCTAssertTrue(arguments.isHeadless)
        XCTAssertTrue(LaunchArguments(["movez", "--smoke"]).smoke)
        XCTAssertFalse(LaunchArguments(["movez"]).isHeadless)
    }
}
