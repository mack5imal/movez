import XCTest
@testable import movez

/// The notice the app asks people to accept is the repository's own HEALTH_AND_SAFETY.md, parsed
/// into blocks. These hold the parser to that file and the acceptance rule to its version.
@MainActor
final class HealthNoticeTests: XCTestCase {
    private func bundled() throws -> HealthNotice {
        try HealthNotice.loadBundled()
    }

    private func text(of block: HealthNotice.Block) -> String {
        switch block {
        case .heading(let text), .paragraph(let text), .bullet(let text), .note(let text): return text
        case .rule: return "---"
        }
    }

    // MARK: - The bundled notice

    func testTheNoticeIsBundled() throws {
        let url = try XCTUnwrap(
            MovezBundle.resources.url(forResource: "HEALTH_AND_SAFETY", withExtension: "md"),
            "Missing HEALTH_AND_SAFETY.md in the app bundle"
        )
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 5_000)
    }

    func testTheBundledNoticeParses() throws {
        let notice = try bundled()
        XCTAssertEqual(notice.title, "Movez — Health, Safety and Terms of Use")
        XCTAssertEqual(notice.version, "1.0")
        XCTAssertEqual(notice.effective, "Effective October 19, 2026")

        let headings = notice.blocks.compactMap { block -> String? in
            if case .heading(let text) = block { return text } else { return nil }
        }
        XCTAssertEqual(headings.count, 12, "sections 0 to 11")
        XCTAssertEqual(headings.first, "0. Movez is unfinished, pre-release software")
        XCTAssertEqual(headings.last, "11. General")
    }

    /// Nothing from the legal review or the README's mock buttons reaches the screen.
    func testNoDraftOrMockTextIsShown() throws {
        for block in try bundled().blocks {
            let text = text(of: block)
            XCTAssertFalse(text.contains("[REVIEW]"), text)
            XCTAssertFalse(text.contains("DRAFT"), text)
            XCTAssertFalse(text.contains("[ "), text)
        }
    }

    func testTheReleaseOfClaimsKeepsItsBold() throws {
        let release = try XCTUnwrap(try bundled().blocks.first { text(of: $0).hasPrefix("**Release of claims.**") })
        let styled = HealthNotice.styled(text(of: release))
        XCTAssertFalse(String(styled.characters).contains("**"), "the asterisks became bold, not text")
        let boldRuns = styled.runs.filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
        XCTAssertEqual(boldRuns.count, 2, "the heading and the negligence clause")
    }

    // MARK: - The parser

    func testWrappedLinesJoinAndEachKindOfBlockParses() throws {
        let notice = try HealthNotice.parse("""
        # Title

        *Notice version 2.1 · Effective today*

        ## 1. First

        A paragraph that
        wraps onto a second line.

        - a bullet that
          also wraps
        - another

        ---

        [ Quit ]    [ I understand and agree ]

        *A closing note.*
        """)
        XCTAssertEqual(notice.title, "Title")
        XCTAssertEqual(notice.version, "2.1")
        XCTAssertEqual(notice.blocks, [
            .heading("1. First"),
            .paragraph("A paragraph that wraps onto a second line."),
            .bullet("a bullet that also wraps"),
            .bullet("another"),
            .rule,
            .note("A closing note.")
        ])
    }

    func testANoticeWithoutAVersionIsRefused() {
        XCTAssertThrowsError(try HealthNotice.parse("# Title\n\nNo version here.")) { error in
            XCTAssertEqual(error as? HealthNoticeError, .versionMissing)
        }
    }

    // MARK: - Acceptance

    func testAcceptanceIsNeededUntilThisVersionIsAccepted() throws {
        let notice = try bundled()
        XCTAssertTrue(NoticeAcceptance.isNeeded(acceptedVersion: nil, notice: notice))
        XCTAssertTrue(NoticeAcceptance.isNeeded(acceptedVersion: "0.9", notice: notice), "an older version asks again")
        XCTAssertFalse(NoticeAcceptance.isNeeded(acceptedVersion: notice.version, notice: notice))
    }

    func testAMissingNoticeIsFatalAndSaysSo() {
        let presenter = RecordingFatalPresenter()
        let notice = Launch.loadNotice(using: { throw HealthNoticeError.resourceMissing }, presenter: presenter)
        XCTAssertNil(notice)
        XCTAssertEqual(presenter.errors.first as? HealthNoticeError, .resourceMissing)
    }

    func testAcceptanceIsStoredAndReadBack() {
        let suite = ScratchDefaults.make()
        let date = Date(timeIntervalSince1970: 1_793_000_000)
        SettingsStore(defaults: suite).acceptNotice(version: "1.0", at: date)

        let reread = SettingsStore(defaults: suite)
        XCTAssertEqual(reread.acceptedNoticeVersion, "1.0")
        XCTAssertEqual(reread.acceptedNoticeAt, date)
    }
}
