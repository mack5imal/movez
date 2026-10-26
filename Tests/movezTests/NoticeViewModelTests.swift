import XCTest
@testable import movez

/// The notice window's rules: nobody accepts a notice they never scrolled through, an acceptance
/// is recorded once with its version and time, and the copy reopened from Settings is read-only.
@MainActor
final class NoticeViewModelTests: XCTestCase {
    private let acceptedAt = Date(timeIntervalSince1970: 1_793_000_000)

    private func makeViewModel(
        mode: NoticeViewModel.Mode,
        settings: SettingsStore? = nil,
        onAgree: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) throws -> NoticeViewModel {
        NoticeViewModel(
            notice: try HealthNotice.loadBundled(),
            mode: mode,
            settings: settings ?? SettingsStore(defaults: ScratchDefaults.make()),
            now: { [acceptedAt] in acceptedAt },
            onAgree: onAgree,
            onQuit: onQuit,
            onClose: onClose
        )
    }

    func testAgreeWaitsForTheEndOfTheNotice() throws {
        let settings = SettingsStore(defaults: ScratchDefaults.make())
        var agreed = 0
        let viewModel = try makeViewModel(mode: .accept, settings: settings, onAgree: { agreed += 1 })

        XCTAssertFalse(viewModel.canAgree)
        XCTAssertEqual(viewModel.hint, "Scroll to the end to continue.")
        viewModel.agree()
        XCTAssertEqual(agreed, 0, "pressing early does nothing")
        XCTAssertNil(settings.acceptedNoticeVersion)

        viewModel.endReached()
        XCTAssertTrue(viewModel.canAgree)
        XCTAssertNil(viewModel.hint)
    }

    func testAgreeRecordsTheVersionAndTimeOnce() throws {
        let settings = SettingsStore(defaults: ScratchDefaults.make())
        var agreed = 0
        let viewModel = try makeViewModel(mode: .accept, settings: settings, onAgree: { agreed += 1 })
        viewModel.endReached()

        viewModel.agree()
        viewModel.agree()

        XCTAssertEqual(agreed, 1, "a second press must not start a second coordinator")
        XCTAssertEqual(settings.acceptedNoticeVersion, "1.0")
        XCTAssertEqual(settings.acceptedNoticeAt, acceptedAt)
        XCTAssertFalse(viewModel.canAgree)
    }

    func testQuitIsAlwaysThere() throws {
        var quit = false
        let viewModel = try makeViewModel(mode: .accept, onQuit: { quit = true })
        viewModel.quit()
        XCTAssertTrue(quit)
    }

    func testReadModeCannotAgreeAndSaysWhenItWasAccepted() throws {
        let settings = SettingsStore(defaults: ScratchDefaults.make())
        settings.acceptNotice(version: "1.0", at: acceptedAt)
        var closed = false
        let viewModel = try makeViewModel(mode: .read, settings: settings, onClose: { closed = true })

        viewModel.endReached()
        XCTAssertFalse(viewModel.canAgree)
        XCTAssertNil(viewModel.hint)
        XCTAssertEqual(
            viewModel.acceptedLine,
            "You accepted version 1.0 on \(NoticeViewModel.dateText(acceptedAt))."
        )
        viewModel.close()
        XCTAssertTrue(closed)
    }

    func testTheVersionLineReadsLikeTheFile() throws {
        XCTAssertEqual(
            try makeViewModel(mode: .accept).versionLine,
            "Notice version 1.0 · Effective October 19, 2026"
        )
    }

    // MARK: - Settings

    func testSettingsShowsTheAcceptanceAndOpensTheNotice() {
        let settings = SettingsStore(defaults: ScratchDefaults.make())
        var opened = false
        let viewModel = SettingsViewModel(
            settings: settings,
            library: RoutineTestSupport.library,
            launchAtLogin: FakeLaunchAtLogin(),
            openNotice: { opened = true }
        )
        XCTAssertNil(viewModel.noticeDetail)

        settings.acceptNotice(version: "1.0", at: acceptedAt)
        XCTAssertEqual(viewModel.noticeDetail, "Accepted \(NoticeViewModel.dateText(acceptedAt)) · version 1.0")

        viewModel.openNotice()
        XCTAssertTrue(opened)
    }
}
