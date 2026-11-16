import XCTest
@testable import movez

final class CaptureSignaturesTests: XCTestCase {
    private var signatures: CaptureSignatures {
        do {
            return try CaptureSignatures.loadBundled()
        } catch {
            XCTFail("capture-signatures.json did not load: \(error)")
            return CaptureSignatures(note: "", signatures: [])
        }
    }

    // MARK: - A bad file is loud

    /// A file that will not load turns screen-share detection off for good, so the shipped one
    /// must load, and say why when it does not.
    func testTheBundledFileLoadsWithoutError() {
        XCTAssertNoThrow(try CaptureSignatures.loadBundled())
    }

    func testAMalformedFileThrowsRatherThanLoadingNothing() {
        let broken = Data(#"{"note": "x", "signatures": [{"name": "No ids"}]}"#.utf8)
        XCTAssertThrowsError(try CaptureSignatures.decode(broken))
        XCTAssertThrowsError(try CaptureSignatures.decode(Data("not json".utf8)))
    }

    /// The two flags read as optional, and now are: an entry that leaves them out is an enabled
    /// signature that matches on its bundle alone, instead of a decoding error for the whole file.
    func testTheFlagsDefaultWhenLeftOut() throws {
        let json = #"{"note": "x", "signatures": [{"name": "Tool", "bundleIds": ["a.b"], "processNames": []}]}"#
        let decoded = try CaptureSignatures.decode(Data(json.utf8))
        XCTAssertEqual(decoded.signatures.first?.enabled, true)
        XCTAssertEqual(decoded.signatures.first?.requireProcessName, false)
        XCTAssertEqual(decoded.firstMatch(bundleIds: ["a.b"], processNames: [])?.name, "Tool")
    }

    func testTheFileLoadsWithEnoughSignatures() {
        XCTAssertGreaterThanOrEqual(signatures.signatures.count, 6)
        XCTAssertFalse(signatures.note.isEmpty, "the heuristic's limitation is documented in the file")
        let names = signatures.signatures.map(\.name)
        XCTAssertTrue(names.contains { $0.contains("Zoom") })
        XCTAssertTrue(names.contains { $0.contains("Teams") })
        XCTAssertTrue(names.contains { $0.contains("OBS") })
        // QuickTime has no row of its own: it records through `screencapture`, which the generic
        // row catches — see testAQuickTimeRecordingIsCaught.
        XCTAssertTrue(names.contains { $0.contains("ScreenFlow") })
        XCTAssertTrue(names.contains { $0.contains("Loom") })
    }

    /// Each enabled signature must catch something no other one does: a row whose removal
    /// changes nothing is one a maintainer will edit expecting an effect it cannot have.
    func testEveryEnabledSignatureEarnsItsPlace() {
        let all = signatures.signatures
        for (index, signature) in all.enumerated() where signature.enabled {
            var others = all
            others.remove(at: index)
            let without = CaptureSignatures(note: "", signatures: others)
            let bundles = Set(signature.bundleIds)
            let processes = Set(signature.processNames)
            XCTAssertNil(
                without.firstMatch(bundleIds: bundles, processNames: processes),
                "\(signature.name) is already covered by another signature"
            )
        }
    }

    /// QuickTime records through `screencapture`, which the generic row catches.
    func testAQuickTimeRecordingIsCaught() {
        XCTAssertEqual(
            signatures.firstMatch(bundleIds: ["com.apple.QuickTimePlayerX"], processNames: ["screencapture"])?.name,
            "macOS screen recording"
        )
        XCTAssertNil(signatures.firstMatch(bundleIds: ["com.apple.QuickTimePlayerX"], processNames: []))
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
