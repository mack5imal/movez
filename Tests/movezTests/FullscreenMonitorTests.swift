import XCTest
@testable import movez

final class FullscreenMonitorTests: XCTestCase {
    private let laptop = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let external = CGRect(x: 1440, y: 0, width: 2560, height: 1440)

    func testAWindowThatFillsAScreenIsFullscreen() {
        XCTAssertTrue(FullscreenMonitor.isFullscreen(windowBounds: laptop, screenFrames: [laptop, external]))
        XCTAssertTrue(FullscreenMonitor.isFullscreen(windowBounds: external, screenFrames: [laptop, external]))
    }

    func testAWindowShortOfTheMenuBarIsNotFullscreen() {
        let windowed = CGRect(x: 0, y: 25, width: 1440, height: 860)
        XCTAssertFalse(FullscreenMonitor.isFullscreen(windowBounds: windowed, screenFrames: [laptop]))

        let almost = CGRect(x: 0, y: 0, width: 1440, height: 860)
        XCTAssertFalse(FullscreenMonitor.isFullscreen(windowBounds: almost, screenFrames: [laptop]))
    }

    func testAPointOfToleranceIsAllowed() {
        let offByOne = CGRect(x: 0.5, y: -0.5, width: 1440.5, height: 899.5)
        XCTAssertTrue(FullscreenMonitor.isFullscreen(windowBounds: offByOne, screenFrames: [laptop]))

        let offByTwo = CGRect(x: 2, y: 0, width: 1440, height: 900)
        XCTAssertFalse(FullscreenMonitor.isFullscreen(windowBounds: offByTwo, screenFrames: [laptop]))
    }

    func testNoScreensMeansNoFullscreen() {
        XCTAssertFalse(FullscreenMonitor.isFullscreen(windowBounds: laptop, screenFrames: []))
    }

    func testAnExcludedAppNeverSuppresses() {
        func reading(_ bundleId: String, exceptions: Set<String>) -> FullscreenReading {
            FullscreenMonitor.reading(
                bundleId: bundleId,
                ownBundleId: "com.kylemack.movez",
                exceptions: exceptions,
                windows: { [self.laptop] },
                screens: { [self.laptop] }
            )
        }
        XCTAssertTrue(reading("com.apple.QuickTimePlayerX", exceptions: ["com.figma.Desktop"]).isFullscreen)
        XCTAssertFalse(reading("com.apple.QuickTimePlayerX", exceptions: ["com.apple.QuickTimePlayerX"]).isFullscreen)
        XCTAssertEqual(
            reading("com.apple.QuickTimePlayerX", exceptions: ["com.apple.QuickTimePlayerX"]).bundleId,
            "com.apple.QuickTimePlayerX",
            "an excepted app is still reported, so the exceptions list can show it"
        )
    }

    func testMovezNeverSuppressesItself() {
        let reading = FullscreenMonitor.reading(
            bundleId: "com.kylemack.movez",
            ownBundleId: "com.kylemack.movez",
            exceptions: [],
            windows: { [self.laptop] },
            screens: { [self.laptop] }
        )
        XCTAssertFalse(reading.isFullscreen, "the overlay fills the screen, and must not suppress its own break")
    }

    func testAnUnnamedAppIsJudgedByItsWindows() {
        let reading = FullscreenMonitor.reading(
            bundleId: nil, ownBundleId: "com.kylemack.movez", exceptions: [],
            windows: { [self.external] }, screens: { [self.laptop, self.external] }
        )
        XCTAssertTrue(reading.isFullscreen)
    }
}
