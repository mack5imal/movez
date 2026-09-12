import AppKit
import XCTest
@testable import movez

final class TokensTests: XCTestCase {
    private func assertRGB(
        _ color: MovezColor,
        _ red: Int,
        _ green: Int,
        _ blue: Int,
        alpha: Double = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let components = color.rgb255
        XCTAssertEqual(components.red, red, "red", file: file, line: line)
        XCTAssertEqual(components.green, green, "green", file: file, line: line)
        XCTAssertEqual(components.blue, blue, "blue", file: file, line: line)
        XCTAssertEqual(color.alpha, alpha, accuracy: 0.001, "alpha", file: file, line: line)
    }

    func testHexColoursMatchTheHandoff() {
        XCTAssertEqual(Tokens.ink.hexString, "#08161f")
        XCTAssertEqual(Tokens.accent.hexString, "#7fc8b7")
        XCTAssertEqual(Tokens.text.hexString, "#e6f1ee")
        XCTAssertEqual(Tokens.text2.hexString, "#a9c3c0")
        XCTAssertEqual(Tokens.text3.hexString, "#5a7a86")
        XCTAssertEqual(Tokens.warn.hexString, "#e2a45f")
        XCTAssertEqual(Tokens.panelSolid.hexString, "#12283a")
    }

    func testRGBAColoursMatchTheHandoff() {
        assertRGB(Tokens.panel, 18, 42, 58, alpha: 0.92)
        assertRGB(Tokens.panelSmall, 18, 42, 58, alpha: 0.94)
        assertRGB(Tokens.panelMenu, 18, 42, 58, alpha: 0.96)
        assertRGB(Tokens.panelBorder, 127, 200, 183, alpha: 0.28)
        assertRGB(Tokens.accentTint, 127, 200, 183, alpha: 0.14)
        assertRGB(Tokens.accentTintSegmented, 127, 200, 183, alpha: 0.12)
        assertRGB(Tokens.accentTintBadge, 127, 200, 183, alpha: 0.10)
        assertRGB(Tokens.secondaryBorder, 127, 200, 183, alpha: 0.35)
        assertRGB(Tokens.rule, 127, 200, 183, alpha: 0.18)
        assertRGB(Tokens.ruleInactive, 127, 200, 183, alpha: 0.25)
        assertRGB(Tokens.ruleSettings, 127, 200, 183, alpha: 0.14)
        assertRGB(Tokens.emptyRing, 127, 200, 183, alpha: 0.25)
        assertRGB(Tokens.dim, 8, 22, 34, alpha: 0.86)
        assertRGB(Tokens.dimEnd, 8, 22, 34, alpha: 0.78)
        assertRGB(Tokens.ringTrack, 8, 22, 31, alpha: 0.15)
    }

    func testRadii() {
        XCTAssertEqual(Tokens.Radius.overlay, 36)
        XCTAssertEqual(Tokens.Radius.panel, 20)
        XCTAssertEqual(Tokens.Radius.toast, 16)
        XCTAssertEqual(Tokens.Radius.menu, 12)
        XCTAssertEqual(Tokens.Radius.row, 7)
        XCTAssertEqual(Tokens.Radius.settings, 12)
        XCTAssertEqual(Tokens.Radius.pill, 999)
        XCTAssertEqual(Tokens.Radius.select, 8)
        XCTAssertEqual(Tokens.Radius.badge, 10)
    }

    func testShadowsAndMetrics() {
        XCTAssertEqual(Tokens.Shadow.overlay.offsetY, 40)
        XCTAssertEqual(Tokens.Shadow.overlay.opacity, 0.5)
        XCTAssertEqual(Tokens.Shadow.panel.offsetY, 24)
        XCTAssertEqual(Tokens.Shadow.panel.opacity, 0.45)
        XCTAssertEqual(Tokens.Shadow.menu.offsetY, 18)
        XCTAssertEqual(Tokens.Shadow.disc.offsetY, 30)
        XCTAssertEqual(Tokens.backdropBlur, 24)

        XCTAssertEqual(Tokens.Metric.overlayCard, CGSize(width: 1000, height: 660))
        XCTAssertEqual(Tokens.Metric.overlayDisc, 300)
        XCTAssertEqual(Tokens.Metric.panelWidth, 400)
        XCTAssertEqual(Tokens.Metric.panelWidthDeferred, 420)
        XCTAssertEqual(Tokens.Metric.panelDisc, 64)
        XCTAssertEqual(Tokens.Metric.toastWidth, 380)
        XCTAssertEqual(Tokens.Metric.menuWidth, 264)
        XCTAssertEqual(Tokens.Metric.menuDisc, 40)
        XCTAssertEqual(Tokens.Metric.settings, CGSize(width: 760, height: 700))
        XCTAssertEqual(Tokens.Metric.togglesize, CGSize(width: 38, height: 22))
    }

    func testOpacityKeepsTheColourAndChangesOnlyTheAlpha() {
        let faded = Tokens.accent.opacity(0.5)
        XCTAssertEqual(faded.hexString, Tokens.accent.hexString)
        XCTAssertEqual(faded.alpha, 0.5)
    }
}
