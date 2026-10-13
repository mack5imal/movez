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
        let fake = FakeFullscreenSource()
        fake.isFullscreen = true
        fake.bundleId = "com.apple.QuickTimePlayerX"
        XCTAssertTrue(fake.reading(exceptions: ["com.figma.Desktop"]).isFullscreen)
        XCTAssertFalse(fake.reading(exceptions: ["com.apple.QuickTimePlayerX"]).isFullscreen)
    }

    func testTheRealMonitorRunsWithoutCrashing() {
        let reading = FullscreenMonitor(ownBundleId: "com.kylemack.movez").reading(exceptions: [])
        // Whatever is frontmost on this Mac right now, which can be movez itself: then it is
        // reported, but never as full screen.
        if reading.bundleId == "com.kylemack.movez" {
            XCTAssertFalse(reading.isFullscreen, "movez never suppresses itself")
        }
    }
}
