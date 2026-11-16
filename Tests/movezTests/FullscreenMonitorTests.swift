import XCTest
@testable import movez

final class FullscreenMonitorTests: XCTestCase {
    private let laptop = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let external = CGRect(x: 1440, y: 0, width: 2560, height: 1440)
    /// A 16-inch MacBook Pro's built-in panel: the frame includes the strip either side of the
    /// camera housing, and macOS puts native fullscreen content below it.
    private let notched = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let notchInset: CGFloat = 32

    private func screens(_ frames: CGRect...) -> [FullscreenMonitor.Screen] {
        frames.map { FullscreenMonitor.Screen(frame: $0) }
    }

    func testAWindowThatFillsAScreenIsFullscreen() {
        XCTAssertTrue(FullscreenMonitor.isFullscreen(windowBounds: laptop, screens: screens(laptop, external)))
        XCTAssertTrue(FullscreenMonitor.isFullscreen(windowBounds: external, screens: screens(laptop, external)))
    }

    func testAWindowShortOfTheMenuBarIsNotFullscreen() {
        let windowed = CGRect(x: 0, y: 25, width: 1440, height: 860)
        XCTAssertFalse(FullscreenMonitor.isFullscreen(windowBounds: windowed, screens: screens(laptop)))

        let almost = CGRect(x: 0, y: 0, width: 1440, height: 860)
        XCTAssertFalse(FullscreenMonitor.isFullscreen(windowBounds: almost, screens: screens(laptop)))
    }

    func testAPointOfToleranceIsAllowed() {
        let offByOne = CGRect(x: 0.5, y: -0.5, width: 1440.5, height: 899.5)
        XCTAssertTrue(FullscreenMonitor.isFullscreen(windowBounds: offByOne, screens: screens(laptop)))

        let offByTwo = CGRect(x: 2, y: 0, width: 1440, height: 900)
        XCTAssertFalse(FullscreenMonitor.isFullscreen(windowBounds: offByTwo, screens: screens(laptop)))
    }

    func testNoScreensMeansNoFullscreen() {
        XCTAssertFalse(FullscreenMonitor.isFullscreen(windowBounds: laptop, screens: []))
    }

    func testAnExcludedAppNeverSuppresses() {
        func reading(_ bundleId: String, exceptions: Set<String>) -> FullscreenReading {
            FullscreenMonitor.reading(
                bundleId: bundleId,
                ownBundleId: "com.kylemack.movez",
                exceptions: exceptions,
                windows: { [self.laptop] },
                screens: { self.screens(self.laptop) }
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
            screens: { self.screens(self.laptop) }
        )
        XCTAssertFalse(reading.isFullscreen, "the overlay fills the screen, and must not suppress its own break")
    }

    func testAnUnnamedAppIsJudgedByItsWindows() {
        let reading = FullscreenMonitor.reading(
            bundleId: nil, ownBundleId: "com.kylemack.movez", exceptions: [],
            windows: { [self.external] }, screens: { self.screens(self.laptop, self.external) }
        )
        XCTAssertTrue(reading.isFullscreen)
    }

    // MARK: - The notch

    /// A native fullscreen window on a notched panel sits inside the safe area, 32 pt short of
    /// the frame at the top. Matched against the whole frame only, it never counted, and breaks
    /// fired over presentations on the built-in display of every notched MacBook.
    func testAFullscreenWindowBelowTheNotchIsFullscreen() {
        let panel = FullscreenMonitor.Screen(frame: notched, topInset: notchInset)
        let belowNotch = CGRect(x: 0, y: 32, width: 1728, height: 1085)
        XCTAssertTrue(FullscreenMonitor.isFullscreen(windowBounds: belowNotch, screens: [panel]))
        XCTAssertTrue(
            FullscreenMonitor.isFullscreen(windowBounds: notched, screens: [panel]),
            "a window drawn over the notch (the 'scale to fit below camera' setting off) still counts"
        )
    }

    func testTheSafeAreaIsOnlyAllowedOnANotchedScreen() {
        let belowNotch = CGRect(x: 0, y: 32, width: 1728, height: 1085)
        XCTAssertFalse(
            FullscreenMonitor.isFullscreen(windowBounds: belowNotch, screens: screens(notched)),
            "a screen with no inset has no safe-area rect to match"
        )
    }

    /// A zoomed window on the notched panel starts under the menu bar, which is taller than the
    /// camera housing, so it is still not mistaken for fullscreen.
    func testAZoomedWindowOnANotchedScreenIsNotFullscreen() {
        let panel = FullscreenMonitor.Screen(frame: notched, topInset: notchInset)
        let zoomed = CGRect(x: 0, y: 38, width: 1728, height: 1079)
        XCTAssertFalse(FullscreenMonitor.isFullscreen(windowBounds: zoomed, screens: [panel]))
    }

    func testTheNotchIsReadPerScreen() {
        let panel = FullscreenMonitor.Screen(frame: notched, topInset: notchInset)
        let monitor = FullscreenMonitor.Screen(frame: CGRect(x: 1728, y: 0, width: 2560, height: 1440))
        let belowNotch = CGRect(x: 0, y: 32, width: 1728, height: 1085)
        let shortExternal = CGRect(x: 1728, y: 32, width: 2560, height: 1408)
        let reading = FullscreenMonitor.reading(
            bundleId: "com.apple.Keynote", ownBundleId: "com.kylemack.movez", exceptions: [],
            windows: { [belowNotch] }, screens: { [panel, monitor] }
        )
        XCTAssertTrue(reading.isFullscreen)
        XCTAssertFalse(FullscreenMonitor.isFullscreen(windowBounds: shortExternal, screens: [panel, monitor]))
    }
}
