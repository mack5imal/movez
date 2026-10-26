import AppKit
import SwiftUI

/// Owns process-level concerns: font registration, accessory activation policy, the coordinator's
/// lifetime, and the head-less command-line entry points used by the build and verification
/// harnesses.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private let arguments = LaunchArguments.current
    private(set) var coordinator: AppCoordinator?
    /// Replaced in tests; the real one shows an alert and quits.
    var fatalPresenter: FatalPresenter = AlertFatalPresenter()
    /// Published so the menu-bar scene picks the view model up the moment the coordinator exists.
    @Published private(set) var menuBar: MenuBarViewModel?
    /// True while the health and safety notice is waiting to be accepted, so the menu can say so.
    @Published private(set) var awaitingNotice = false
    private var settingsWindow: SettingsWindowController?
    private let noticeWindow = NoticeWindowController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        MovezFont.register()
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit-test bundle is hosted by this app, so `xcodebuild test` launches it for real.
        // Left to itself it would build a coordinator on the developer's own state and history
        // files and count phantom breaks into them — every test run inflating the numbers the
        // menu bar shows. Tests build their own coordinators against in-memory stores.
        guard !Self.isHostingTests else { return }

        guard arguments.isHeadless else {
            launch()
            return
        }
        if arguments.probeSignals {
            SignalProbe.run { exit($0) }
            return
        }
        if arguments.overlayHygiene {
            OverlayHygiene.run(outPath: arguments.out) { exit($0) }
            return
        }
        if arguments.panelHygiene {
            PanelHygiene.run { exit($0) }
            return
        }
        if let surface = arguments.snapshot {
            SnapshotRenderer.runCLI(surface: surface, out: arguments.out) { exit($0) }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [arguments] in
            if arguments.smoke {
                // Intentional stdout line: the build harness asserts on it.
                print("movez smoke ok")
                fflush(stdout)
            }
            exit(0)
        }
    }

    /// True when this process exists to host an XCTest bundle rather than to serve the user.
    static var isHostingTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Loads what the app cannot run without, then starts it, or first asks for the health and
    /// safety notice to be accepted. Until it is, nothing is scheduled, polled or written: the
    /// coordinator does not exist yet. A library or notice that will not load is fatal and loud.
    private func launch() {
        guard let library = Launch.loadLibrary(presenter: fatalPresenter),
              let notice = Launch.loadNotice(presenter: fatalPresenter) else { return }
        let settings = SettingsStore()
        guard NoticeAcceptance.isNeeded(acceptedVersion: settings.acceptedNoticeVersion, notice: notice) else {
            startCoordinator(library: library, notice: notice, settings: settings)
            return
        }
        awaitingNotice = true
        noticeWindow.show(NoticeViewModel(
            notice: notice,
            mode: .accept,
            settings: settings,
            onAgree: { [weak self] in
                guard let self else { return }
                noticeWindow.close()
                awaitingNotice = false
                startCoordinator(library: library, notice: notice, settings: settings)
            },
            onQuit: { NSApp.terminate(nil) }
        ))
    }

    /// The menu's "Show notice", while it waits to be accepted.
    func showPendingNotice() {
        noticeWindow.bringForward()
    }

    /// Builds the coordinator from the bundled library and the user's saved state.
    private func startCoordinator(library: MovementLibrary, notice: HealthNotice, settings: SettingsStore) {
        let historyStore = try? FileHistoryStore.historyFile()
        let snapshotStore = try? FileSnapshotStore.stateFile()
        let coordinator = AppCoordinator(
            library: library,
            settings: settings,
            history: historyStore.map { HistoryStore(store: $0) } ?? HistoryStore(),
            clock: SystemClock(),
            snapshotStore: snapshotStore
        )
        coordinator.attachSystemSignals()
        attachUI(to: coordinator, settings: settings)
        coordinator.start()
        self.coordinator = coordinator
        menuBar = MenuBarViewModel(coordinator: coordinator)

        let settingsViewModel = SettingsViewModel(
            settings: settings,
            library: library,
            openNotice: { [weak self] in
                guard let self else { return }
                noticeWindow.show(NoticeViewModel(
                    notice: notice,
                    mode: .read,
                    settings: settings,
                    onClose: { [weak self] in self?.noticeWindow.close() }
                ))
            },
            onChange: { [weak coordinator] in coordinator?.settingsChanged() }
        )
        settingsWindow = SettingsWindowController(viewModel: settingsViewModel) {
            DebugViewModel(coordinator: coordinator)
        }
    }

    /// Registers the surfaces that turn scheduler effects into windows and sound.
    private func attachUI(to coordinator: AppCoordinator, settings: SettingsStore) {
        let chimes = GatedChimePlayer(wrapping: AudioChimePlayer(), isEnabled: { settings.soundsEnabled })
        let sink = CompositeEffectSink([
            OverlayEffectSink(controller: OverlayWindowController(), chimes: chimes),
            PanelEffectSink(controller: PanelWindowController(), chimes: chimes)
        ])
        coordinator.register(sink: sink)
    }
}
