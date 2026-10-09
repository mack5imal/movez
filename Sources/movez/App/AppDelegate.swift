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
    private var settingsWindow: SettingsWindowController?

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
            startCoordinator()
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

    /// Builds the coordinator from the bundled library and the user's saved state. A library that
    /// will not load is fatal and loud: an app that quietly serves no movements is worse than one
    /// that says why it cannot.
    private func startCoordinator() {
        guard let library = Launch.loadLibrary(presenter: fatalPresenter) else { return }
        let settings = SettingsStore()
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
