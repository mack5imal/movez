import XCTest
@testable import movez

final class CaptureSignaturesTests: XCTestCase {
    private var signatures: CaptureSignatures {
        guard let bundled = CaptureSignatures.bundled() else {
            XCTFail("capture-signatures.json is missing from the bundle")
            return CaptureSignatures(note: "", signatures: [])
        }
        return bundled
    }

    func testTheFileLoadsWithEnoughSignatures() {
        XCTAssertGreaterThanOrEqual(signatures.signatures.count, 6)
        XCTAssertFalse(signatures.note.isEmpty, "the heuristic's limitation is documented in the file")
        let names = signatures.signatures.map(\.name)
        XCTAssertTrue(names.contains { $0.contains("Zoom") })
        XCTAssertTrue(names.contains { $0.contains("Teams") })
        XCTAssertTrue(names.contains { $0.contains("OBS") })
        XCTAssertTrue(names.contains { $0.contains("QuickTime") })
        XCTAssertTrue(names.contains { $0.contains("ScreenFlow") })
        XCTAssertTrue(names.contains { $0.contains("Loom") })
    }

    func testZoomOnlyMatchesWithItsShareHelper() {
        XCTAssertNil(signatures.firstMatch(bundleIds: ["us.zoom.xos"], processNames: ["zoom.us"]))
        XCTAssertEqual(
            signatures.firstMatch(bundleIds: ["us.zoom.xos"], processNames: ["CptHost"])?.name,
            "Zoom screen share"
        )
    }

    func testAToolThatRunsAllDayDoesNotSuppressOnItsOwn() {
        // Verified on a real machine: Loom sits in the background with its recorder helper
        // already running, so its presence says nothing about whether a recording is live.
        XCTAssertNil(signatures.firstMatch(bundleIds: ["com.loom.desktop"], processNames: ["loom-recorder-production"]))
        let loom = signatures.signatures.first { $0.name == "Loom" }
        XCTAssertEqual(loom?.enabled, false)
        XCTAssertNotNil(loom?.disabledReason)
    }

    func testAlwaysOnRecordersMatchOnPresence() {
        XCTAssertEqual(
            signatures.firstMatch(bundleIds: ["com.obsproject.obs-studio"], processNames: [])?.name,
            "OBS Studio"
        )
        XCTAssertEqual(
            signatures.firstMatch(bundleIds: [], processNames: ["screencapture"])?.name,
            "macOS screen recording"
        )
        XCTAssertNil(signatures.firstMatch(bundleIds: ["com.apple.Safari"], processNames: ["Safari"]))
    }

    func testOnlyATruncatedNameIsAllowedToMatchOnAPrefix() {
        XCTAssertTrue(CaptureSignature.namesMatch("CptHost", "CptHost"))
        XCTAssertFalse(CaptureSignature.namesMatch("Finder", "CptHost"))

        // A name that filled proc_name's buffer is clipped, and matches what it is a prefix of.
        let clipped = String(repeating: "a", count: CaptureSignature.nameLimit)
        XCTAssertTrue(CaptureSignature.namesMatch(clipped, clipped + " (Screen Share)"))
        XCTAssertFalse(CaptureSignature.namesMatch(String(clipped.dropLast()), clipped + " (Screen Share)"))
    }

    /// The overlay ⌘⇧5 leaves running is called `screencaptureui`. Matching it against the
    /// `screencapture` signature suppressed every break for as long as it lingered.
    func testTheScreenshotOverlayDoesNotCountAsARecording() {
        XCTAssertFalse(CaptureSignature.namesMatch("screencaptureui", "screencapture"))
        XCTAssertNil(signatures.firstMatch(bundleIds: [], processNames: ["screencaptureui"]))
        XCTAssertEqual(
            signatures.firstMatch(bundleIds: [], processNames: ["screencapture"])?.name,
            "macOS screen recording",
            "the real recorder still matches"
        )
    }

    func testTheRealMonitorReadsTheBundledFile() {
        let monitor = ScreenCaptureMonitor()
        XCTAssertGreaterThanOrEqual(monitor.signatureCount, 6)
        XCTAssertGreaterThanOrEqual(monitor.enabledSignatureCount, 5)
        XCTAssertFalse(ScreenCaptureMonitor.runningProcessNames().isEmpty, "the process list is readable")
    }

    func testAnInjectedProcessListDrivesTheMonitor() {
        let monitor = ScreenCaptureMonitor(
            signatures: CaptureSignatures(
                note: "test",
                signatures: [
                    CaptureSignature(
                        name: "Fake recorder",
                        bundleIds: [],
                        processNames: ["fake-recorder"],
                        requireProcessName: false
                    )
                ]
            ),
            processLister: { ["fake-recorder"] }
        )
        XCTAssertTrue(monitor.isCaptured())
        XCTAssertEqual(monitor.matchedSignature()?.name, "Fake recorder")
    }
}
